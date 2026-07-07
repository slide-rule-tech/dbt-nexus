{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['thread_id']),
    unique_key='thread_id',
    on_schema_change='append_new_columns',
    tags=['gmail', 'normalized']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_watermark_ingested_at', 'thread_id']) }}

-- Cross-account normalized threads: Group per-account threads by first_message_id_header
--
-- Touched-group rollup. Child clock = the upstream rollup's
-- _watermark_ingested_at (its _ingested_at is a frozen MIN). Known no-delete
-- caveat: the group key IS first_message_id_header, so a late-arriving
-- earlier message re-keys its thread — the new-key row is emitted correctly
-- and the stale old-key row lingers until the next --full-refresh.
WITH per_account_threads_all AS (
    SELECT * FROM {{ ref('gmail_threads_by_account') }}
),

{% if is_incremental() %}
touched_thread_keys AS (
    SELECT DISTINCT first_message_id_header
    FROM per_account_threads_all
    WHERE _watermark_ingested_at > {{ nexus.nexus_incremental_watermark_literal('_watermark_ingested_at') }}
      AND first_message_id_header IS NOT NULL
),
{% endif %}

per_account_threads AS (
    SELECT t.* FROM per_account_threads_all t
    {% if is_incremental() %}
    INNER JOIN touched_thread_keys tk ON t.first_message_id_header = tk.first_message_id_header
    {% endif %}
),

grouped as (
    SELECT 
        first_message_id_header as thread_id,
        {% if target.type == 'bigquery' %}ARRAY_AGG(subject ORDER BY first_message_sent_at ASC LIMIT 1)[OFFSET(0)]{% else %}first(subject ORDER BY first_message_sent_at ASC){% endif %} as subject,
        {% if target.type == 'bigquery' %}ARRAY_AGG(raw_subject ORDER BY first_message_sent_at ASC LIMIT 1)[OFFSET(0)]{% else %}first(raw_subject ORDER BY first_message_sent_at ASC){% endif %} as raw_subject,
        MIN(first_message_sent_at) as first_message_sent_at,
        MAX(last_message_sent_at) as last_message_sent_at,
        
        -- Create JSON object mapping email (stream_id) to gmail_thread_id
        -- Format: {"email1": "thread_id1", "email2": "thread_id2"}
        CONCAT(
            '{',
            STRING_AGG(
                CONCAT('"', _stream_id, '": "', gmail_thread_id, '"'),
                ', '
                ORDER BY _stream_id
            ),
            '}'
        ) as gmail_thread_ids,
        -- Create JSON object mapping email (stream_id) to label_ids array
        -- Format: {"email1": ["label1", "label2"], "email2": ["label3"]}
        CONCAT(
            '{',
            STRING_AGG(
                CONCAT(
                    '"', _stream_id, '": ',
                    TO_JSON_STRING(label_ids)
                ),
                ', '
                ORDER BY _stream_id
            ),
            '}'
        ) as label_ids,
        MIN(_ingested_at) as _ingested_at,
        MAX(_watermark_ingested_at) as _watermark_ingested_at,
    FROM per_account_threads
    WHERE first_message_id_header IS NOT NULL
    GROUP BY first_message_id_header
),

-- Get all unique label IDs across all streams for each thread
all_labels AS (
    SELECT 
        first_message_id_header,
        ARRAY(
            SELECT DISTINCT label_id
            FROM UNNEST(label_ids) as label_id
            ORDER BY label_id
        ) as all_label_ids
    FROM (
        SELECT 
            first_message_id_header,
            {% if target.type == 'bigquery' %}ARRAY_CONCAT_AGG(label_ids){% else %}flatten(array_agg(label_ids)){% endif %} as label_ids
        FROM per_account_threads
        WHERE first_message_id_header IS NOT NULL
        GROUP BY first_message_id_header
    )
)

SELECT 
    g.thread_id,
    g.subject,
    g.raw_subject,
    g.first_message_sent_at,
    g.last_message_sent_at,
    g.gmail_thread_ids,
    g.label_ids,
    al.all_label_ids,
    g._ingested_at,
    g._watermark_ingested_at
FROM grouped g
LEFT JOIN all_labels al
    ON g.thread_id = al.first_message_id_header