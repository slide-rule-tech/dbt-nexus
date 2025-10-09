{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'events', 'google_calendar']
) }}

-- Union all event types using dbt_utils for column handling
-- Future: add google_calendar_label_events if needed
{{ dbt_utils.union_relations(
    relations=[
        ref('google_calendar_event_events')
    ]
) }}

order by occurred_at desc
