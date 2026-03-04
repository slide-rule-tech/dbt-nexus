{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'events']
) }}

-- Extract message events from normalized gmail messages
SELECT
    {{ nexus.create_nexus_id('event', ['message_id']) }} as event_id,
    sent_at as occurred_at,
    'message sent' as event_name,
    'email' as event_type,
    subject as event_description,
    CASE
        WHEN COALESCE(is_automated_or_bulk_message, FALSE) THEN -10
        ELSE 0
    END as significance,
    'gmail' as source,
    'gmail_message_events' as source_table,
    _ingested_at,
    
    -- Additional fields
    message_id,
    thread_id,
    gmail_message_ids,
    gmail_thread_ids,
    sent_at,
    subject,
    in_reply_to,
    auto_submitted_header,
    precedence_header,
    list_id_header,
    list_unsubscribe_header,
    x_auto_response_suppress_header,
    x_autoreply_header,
    x_autorespond_header,
    is_automated_or_bulk_message,
    raw_subject,
    snippet,
    size_estimate,
    label_ids,
    all_label_ids
    
FROM {{ ref('gmail_messages') }}

