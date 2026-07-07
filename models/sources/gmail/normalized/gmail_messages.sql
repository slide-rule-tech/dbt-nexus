{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['message_id']),
    unique_key='message_id',
    on_schema_change='append_new_columns',
    tags=['gmail', 'normalized']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_watermark_ingested_at', 'message_id']) }}

{% if is_incremental() %}
{% set wm = nexus.nexus_incremental_watermark_literal('_watermark_ingested_at') %}
{% endif %}

-- Cross-account normalized messages: Group per-account messages by message_id_header
-- Join with per-account threads to get thread_id from first_message_id_header
--
-- Touched-group rollup, WIDENED touched-set: thread_id routes through the
-- per-account thread's first_message_id_header, so when a thread gains a
-- message, every message of that thread must be recomputed — touched
-- headers = batch messages UNION all messages of touched threads. A
-- batch-only touched-set would leave the thread's other messages stale.
WITH per_account_messages_all AS (
    SELECT * FROM {{ ref('gmail_messages_by_account') }}
),

per_account_threads AS (
    SELECT * FROM {{ ref('gmail_threads_by_account') }}
),

{% if is_incremental() %}
touched_headers AS (
    SELECT DISTINCT message_id_header
    FROM per_account_messages_all
    WHERE _ingested_at > {{ wm }}
      AND message_id_header IS NOT NULL
    UNION DISTINCT
    SELECT DISTINCT m.message_id_header
    FROM per_account_messages_all m
    INNER JOIN per_account_threads t
    {{ nexus.nexus_incremental_touched_join('m', 't', ['gmail_thread_id', '_account', '_stream_id']) }}
    WHERE t._watermark_ingested_at > {{ wm }}
      AND m.message_id_header IS NOT NULL
),
{% endif %}

per_account_messages AS (
    SELECT m.* FROM per_account_messages_all m
    {% if is_incremental() %}
    INNER JOIN touched_headers th ON m.message_id_header = th.message_id_header
    {% endif %}
),

-- Cross-account deduplication: group by message_id_header, keep latest
grouped_messages AS (
    SELECT 
        message_id_header as message_id,
        message_id_header,
        {% if target.type == 'bigquery' %}ARRAY_AGG(in_reply_to ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(in_reply_to ORDER BY sent_at DESC){% endif %} as in_reply_to,
        {% if target.type == 'bigquery' %}ARRAY_AGG(auto_submitted_header ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(auto_submitted_header ORDER BY sent_at DESC){% endif %} as auto_submitted_header,
        {% if target.type == 'bigquery' %}ARRAY_AGG(precedence_header ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(precedence_header ORDER BY sent_at DESC){% endif %} as precedence_header,
        {% if target.type == 'bigquery' %}ARRAY_AGG(list_id_header ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(list_id_header ORDER BY sent_at DESC){% endif %} as list_id_header,
        {% if target.type == 'bigquery' %}ARRAY_AGG(list_unsubscribe_header ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(list_unsubscribe_header ORDER BY sent_at DESC){% endif %} as list_unsubscribe_header,
        {% if target.type == 'bigquery' %}ARRAY_AGG(x_auto_response_suppress_header ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(x_auto_response_suppress_header ORDER BY sent_at DESC){% endif %} as x_auto_response_suppress_header,
        {% if target.type == 'bigquery' %}ARRAY_AGG(x_autoreply_header ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(x_autoreply_header ORDER BY sent_at DESC){% endif %} as x_autoreply_header,
        {% if target.type == 'bigquery' %}ARRAY_AGG(x_autorespond_header ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(x_autorespond_header ORDER BY sent_at DESC){% endif %} as x_autorespond_header,
        {% if target.type == 'bigquery' %}LOGICAL_OR{% else %}BOOL_OR{% endif %}(COALESCE(is_automated_or_bulk_message, FALSE)) as is_automated_or_bulk_message,
        MAX(sent_at) as sent_at,
        {% if target.type == 'bigquery' %}ARRAY_AGG(raw_subject ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(raw_subject ORDER BY sent_at DESC){% endif %} as raw_subject,
        {% if target.type == 'bigquery' %}ARRAY_AGG(subject ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(subject ORDER BY sent_at DESC){% endif %} as subject,
        {% if target.type == 'bigquery' %}ARRAY_AGG(raw_record ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(raw_record ORDER BY sent_at DESC){% endif %} as raw_record,
        {% if target.type == 'bigquery' %}ARRAY_AGG(snippet ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(snippet ORDER BY sent_at DESC){% endif %} as snippet,
        {% if target.type == 'bigquery' %}ARRAY_AGG(size_estimate ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(size_estimate ORDER BY sent_at DESC){% endif %} as size_estimate,
        'gmail' as source,
        MAX(_ingested_at) as _ingested_at,
        MAX(_ingested_at) as _watermark_ingested_at,
        -- Get the latest gmail_thread_id and _account for joining with threads
        {% if target.type == 'bigquery' %}ARRAY_AGG(gmail_thread_id ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(gmail_thread_id ORDER BY sent_at DESC){% endif %} as last_gmail_thread_id,
        {% if target.type == 'bigquery' %}ARRAY_AGG(_account ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(_account ORDER BY sent_at DESC){% endif %} as _account,
        -- Create JSON object mapping email (stream_id) to gmail_message_id
        -- Format: {"email1": "message_id1", "email2": "message_id2"}
        CONCAT(
            '{',
            STRING_AGG(
                CONCAT('"', _stream_id, '": "', gmail_message_id, '"'),
                ', '
                ORDER BY _stream_id
            ),
            '}'
        ) as gmail_message_ids,
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
        ) as label_ids
    FROM per_account_messages
    WHERE message_id_header IS NOT NULL
    GROUP BY message_id_header
),

-- Get all unique label IDs across all streams for each message
all_labels AS (
    SELECT 
        message_id_header,
        ARRAY(
            SELECT DISTINCT label_id
            FROM UNNEST(label_ids) as label_id
            ORDER BY label_id
        ) as all_label_ids
    FROM (
        SELECT 
            message_id_header,
            {% if target.type == 'bigquery' %}ARRAY_CONCAT_AGG(label_ids){% else %}flatten(array_agg(label_ids)){% endif %} as label_ids
        FROM per_account_messages
        WHERE message_id_header IS NOT NULL
        GROUP BY message_id_header
    )
),

joined as (
    SELECT 
        gm.message_id,
        gm.sent_at,
        pat.first_message_id_header as thread_id,
        gm.subject,
        gm.in_reply_to,
        gm.auto_submitted_header,
        gm.precedence_header,
        gm.list_id_header,
        gm.list_unsubscribe_header,
        gm.x_auto_response_suppress_header,
        gm.x_autoreply_header,
        gm.x_autorespond_header,
        gm.is_automated_or_bulk_message,
        gm.raw_subject,
        gm.raw_record,
        gm.snippet,
        gm.size_estimate,
        gm.source,
        gm._ingested_at,
        gm._watermark_ingested_at,
        gm.gmail_message_ids,
        gm.gmail_thread_ids,
        gm.label_ids,
        al.all_label_ids
    FROM grouped_messages gm
    LEFT JOIN per_account_threads pat 
        ON gm.last_gmail_thread_id = pat.gmail_thread_id
        AND gm._account = pat._account
    LEFT JOIN all_labels al
        ON gm.message_id_header = al.message_id_header
)

select * from joined
