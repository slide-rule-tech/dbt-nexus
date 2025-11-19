{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'events']
) }}

-- Extract message events from normalized gmail messages
SELECT
    {{ nexus.create_nexus_id('event', ['message_id']) }} as event_id,
    sent_at as occurred_at,
    'message_sent' as event_name,
    'email' as event_type,
    subject as event_description,
    'gmail' as source,
    null as value,
    null as value_unit,
    
    -- Additional context
    message_id,
    thread_id,
    gmail_message_id,
    message_id_header,
    sent_at,
    subject,
    body,
    attachments_array,
    ARRAY_LENGTH(REGEXP_EXTRACT_ALL(COALESCE(body, ''), r'\b\w+\b')) as body_word_count,
    IFNULL(ARRAY_LENGTH(attachments_array), 0) as attachments_count,
    'gmail_message_events' as source_table,
    _ingested_at
FROM {{ ref('gmail_messages') }}
WHERE sent_at IS NOT NULL
ORDER BY sent_at DESC
