{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'events']
) }}

WITH google_calendar_events_normalized AS (
    SELECT * FROM {{ ref('google_calendar_events_normalized') }}
)

SELECT
    {{ nexus.create_nexus_id('event', ['calendar_event_id', 'start_time']) }} as event_id,
    start_time as occurred_at,
    event_name,
    event_description,
    NULL as event_value,
    NULL as value_unit,
    CASE 
        WHEN has_external_attendees THEN 3
        ELSE 2
    END as event_significance,
    'calendar_event' as event_type,
    source,
    synced_at as _ingested_at,
    nexus_event_id,
    calendar_event_id,
    summary,
    location,
    end_time,
    organizer,
    creator,
    attendees
FROM google_calendar_events_normalized
WHERE start_time IS NOT NULL

