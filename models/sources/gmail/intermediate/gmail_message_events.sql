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
    
    -- Additional context
    message_id,
    thread_id,
    _ingested_at
FROM {{ ref('gmail_messages') }}
WHERE sent_at IS NOT NULL
ORDER BY sent_at DESC
