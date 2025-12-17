{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'events']
) }}

-- Extract message events from normalized gmail messages
WITH events_raw AS (
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
        'gmail_message_events' as source_table,
        _ingested_at
    FROM {{ ref('gmail_messages') }}
    WHERE sent_at IS NOT NULL
),

-- Deduplicate: same event_id can appear from multiple streams/ingestions
-- Keep the row with the most recent _ingested_at
deduplicated_events AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY event_id 
            ORDER BY _ingested_at DESC
        ) as rn
    FROM events_raw
)

SELECT
    event_id,
    occurred_at,
    event_name,
    event_type,
    event_description,
    source,
    value,
    value_unit,
    message_id,
    thread_id,
    gmail_message_id,
    message_id_header,
    sent_at,
    subject,
    source_table,
    _ingested_at
FROM deduplicated_events
WHERE rn = 1
ORDER BY sent_at DESC
