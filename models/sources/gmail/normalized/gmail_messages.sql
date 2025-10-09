{{ config(
    enabled=var('nexus', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized']
) }}

-- Normalized layer: clean, deduplicated messages with explicit columns
select
    event_id,
    occurred_at,
    message_id,
    thread_id,
    sender_raw,
    recipients_raw,
    subject,
    body,
    sender,
    recipients,
    raw_record,
    synced_at,
    source
from {{ ref('gmail_messages_base') }}
-- Deduplication: keep latest message per message_id
qualify row_number() over (partition by message_id order by occurred_at desc) = 1

