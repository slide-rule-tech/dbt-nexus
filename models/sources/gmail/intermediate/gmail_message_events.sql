{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'events']
) }}

-- Extract message events from normalized gmail messages
select
    event_id,
    occurred_at,
    'message_sent' as event_name,
    'email' as event_type,
    subject as event_description,
    'gmail' as source,
    
    -- Additional context
    message_id,
    thread_id,
    sender,
    recipients,
    synced_at as _ingested_at
from {{ ref('gmail_messages') }}
where occurred_at is not null
order by occurred_at desc

