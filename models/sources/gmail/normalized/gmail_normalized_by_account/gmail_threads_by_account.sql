{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['gmail_thread_id', '_account']),
    unique_key=['gmail_thread_id', '_account', '_stream_id'],
    on_schema_change='append_new_columns',
    tags=['gmail', 'normalized', 'by_account']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_watermark_ingested_at', 'gmail_thread_id']) }}

{% set group_keys = ['gmail_thread_id', '_account', '_stream_id'] %}

-- Per-account normalized threads: Aggregate messages by gmail_thread_id (per account)
-- Uses Gmail's native thread_id for per-account threading
--
-- Touched-group rollup (see nexus_incremental_touched_groups.sql): children
-- are append-only, so touched groups can only grow; recomputing them from
-- full upstream and merging on the output grain needs no delete leg. Two
-- scans by design: (1) batch scan for touched keys (partition-pruned via
-- the constant watermark literal), (2) full-history scan joined to touched
-- keys — compute and write shrink to the touched groups' children.
WITH
{% if is_incremental() %}
touched_groups AS (
    {{ nexus.nexus_incremental_touched_groups(ref('gmail_messages_by_account'), group_keys) }}
),
{% endif %}
messages AS (
    SELECT m.* FROM {{ ref('gmail_messages_by_account') }} m
    {% if is_incremental() %}
    INNER JOIN touched_groups tg
    {{ nexus.nexus_incremental_touched_join('m', 'tg', group_keys) }}
    {% endif %}
),

thread_summary AS (
    SELECT
        gmail_thread_id,
        _account,
        _stream_id,
        
        -- Thread metadata
        COUNT(*) as message_count,
        COUNT(DISTINCT gmail_message_id) as gmail_message_count,
        
        -- Subject (use the earliest message's subject)
        {% if target.type == 'bigquery' %}ARRAY_AGG(subject ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)]{% else %}first(subject ORDER BY sent_at ASC){% endif %} as subject,
        {% if target.type == 'bigquery' %}ARRAY_AGG(raw_subject ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)]{% else %}first(raw_subject ORDER BY sent_at ASC){% endif %} as raw_subject,
        
        -- Timestamps
        MIN(sent_at) as first_message_sent_at,
        MAX(sent_at) as last_message_sent_at,
        MIN(_ingested_at) as first_ingested_at,
        MAX(_ingested_at) as last_ingested_at,
        
        -- Root message info (earliest gmail_message_id)
        {% if target.type == 'bigquery' %}ARRAY_AGG(gmail_message_id ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)]{% else %}first(gmail_message_id ORDER BY sent_at ASC){% endif %} as root_gmail_message_id,
        
        -- First message_id_header (earliest message's message_id_header for cross-account linking)
        {% if target.type == 'bigquery' %}ARRAY_AGG(message_id_header ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)]{% else %}first(message_id_header ORDER BY sent_at ASC){% endif %} as first_message_id_header,
        
        -- Gmail message IDs in thread
        ARRAY_AGG(DISTINCT gmail_message_id) as gmail_message_ids
    FROM messages
    WHERE gmail_thread_id IS NOT NULL
      AND _account IS NOT NULL
    GROUP BY gmail_thread_id, _account, _stream_id
),

-- Get all unique label IDs from all messages in each thread
thread_labels AS (
    SELECT 
        gmail_thread_id,
        _account,
        _stream_id,
        ARRAY(
            SELECT DISTINCT label_id
            FROM UNNEST(label_ids) as label_id
            ORDER BY label_id
        ) as label_ids
    FROM (
        SELECT 
            gmail_thread_id,
            _account,
            _stream_id,
            {% if target.type == 'bigquery' %}ARRAY_CONCAT_AGG(label_ids){% else %}flatten(array_agg(label_ids)){% endif %} as label_ids
        FROM messages
        WHERE gmail_thread_id IS NOT NULL
          AND _account IS NOT NULL
        GROUP BY gmail_thread_id, _account, _stream_id
    )
)

SELECT 
    ts.gmail_thread_id,
    ts.message_count,
    ts.gmail_message_count,
    ts.subject,
    ts.raw_subject,
    ts.first_message_sent_at,
    ts.last_message_sent_at,
    ts.root_gmail_message_id,
    ts.first_message_id_header,
    ts.first_ingested_at as _ingested_at,
    ts.last_ingested_at as _watermark_ingested_at,
    ts._account,
    ts._stream_id,
    tl.label_ids
FROM thread_summary ts
LEFT JOIN thread_labels tl
    ON ts.gmail_thread_id = tl.gmail_thread_id
    AND ts._account = tl._account
    AND ts._stream_id = tl._stream_id

