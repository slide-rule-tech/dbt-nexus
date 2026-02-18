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
    raw_subject,
    snippet,
    size_estimate,
    label_ids,
    all_label_ids
    
FROM {{ ref('gmail_messages') }}

