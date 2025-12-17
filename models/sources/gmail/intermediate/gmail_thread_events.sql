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
    'gmail' as source,
    null as value,
    null as value_unit,
    'gmail_thread_events' as source_table,
    _ingested_at,
    
    -- Additional fields
    thread_id,
    gmail_thread_ids,
    first_message_sent_at,
    last_message_sent_at,
    subject,
    raw_subject,
    label_ids,
    all_label_ids
    
FROM {{ ref('gmail_threads') }}

