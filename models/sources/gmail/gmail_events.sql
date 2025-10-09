{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'events', 'gmail']
) }}

-- Union all event types using dbt_utils for column handling
-- Future: add gmail_label_events, gmail_thread_events
{{ dbt_utils.union_relations(
    relations=[
        ref('gmail_message_events')
    ]
) }}

order by occurred_at desc
