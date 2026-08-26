{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'dimensions', 'google_calendar']
) }}

-- Union layer - All event dimensions from Google Calendar.
--
-- The model NAME is load-bearing: process_event_dimensions resolves
-- ref(source_name ~ '_event_dimensions') by convention for every source
-- configured with `dimensions: true`.
{{ dbt_utils.union_relations(
    relations=[
        ref('google_calendar_meeting_dimensions')
    ]
) }}
