{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['event_id']),
    unique_key='event_id',
    on_schema_change='append_new_columns',
    tags=['gmail', 'intermediate', 'events']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'event_id']) }}

-- Extract thread started events from normalized gmail threads
--
-- Rollup-child clock rule: gmail_threads' _ingested_at is a frozen MIN, so
-- events are stamped from its _watermark_ingested_at — otherwise gmail_events
-- would never re-merge a thread's row when the thread gains messages (its
-- last_message_sent_at, labels etc. would freeze at first sight).
SELECT
    {{ nexus.create_nexus_id('event', ['thread_id', "'thread started'"]) }} as event_id,
    first_message_sent_at as occurred_at,
    'thread started' as event_name,
    'email' as event_type,
    subject as event_description,
    0 as significance,
    'gmail' as source,
    'gmail_thread_events' as source_table,
    _watermark_ingested_at as _ingested_at,
    
    -- Additional fields
    thread_id,
    gmail_thread_ids,
    first_message_sent_at,
    last_message_sent_at,
    subject,
    CAST(NULL AS STRING) as in_reply_to,
    CAST(NULL AS STRING) as auto_submitted_header,
    CAST(NULL AS STRING) as precedence_header,
    CAST(NULL AS STRING) as list_id_header,
    CAST(NULL AS STRING) as list_unsubscribe_header,
    CAST(NULL AS STRING) as x_auto_response_suppress_header,
    CAST(NULL AS STRING) as x_autoreply_header,
    CAST(NULL AS STRING) as x_autorespond_header,
    CAST(NULL AS BOOL) as is_automated_or_bulk_message,
    raw_subject,
    label_ids,
    all_label_ids
    
FROM {{ ref('gmail_threads') }}
{% if is_incremental() %}
WHERE _watermark_ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
{% endif %}

