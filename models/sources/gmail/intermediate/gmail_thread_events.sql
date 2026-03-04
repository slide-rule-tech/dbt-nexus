{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'events']
) }}

-- Extract thread started events from normalized gmail threads
SELECT
    {{ nexus.create_nexus_id('event', ['thread_id', '"thread started"']) }} as event_id,
    first_message_sent_at as occurred_at,
    'thread started' as event_name,
    'email' as event_type,
    subject as event_description,
    0 as significance,
    'gmail' as source,
    'gmail_thread_events' as source_table,
    _ingested_at,
    
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

