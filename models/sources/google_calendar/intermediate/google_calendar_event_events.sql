{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'events']
) }}

-- Extract calendar events from normalized google_calendar_events
SELECT
    {{ nexus.create_nexus_id('event', ['event_id']) }} as event_id,
    start_time as occurred_at,
    CASE 
        WHEN has_external_attendees THEN 'external_meeting'
        ELSE 'internal_meeting'
    END as event_name,
    COALESCE(summary, 'Calendar Event') as event_description,
    null as value,
    'test' as value_unit,
    CASE 
        WHEN has_external_attendees THEN 3
        ELSE 2
    END as event_significance,
    'calendar_event' as event_type,
    source,
    _ingested_at,
    event_id as calendar_event_key,
    calendar_id,
    ical_uid,
    calendar_event_id,
    instance_start,
    summary,
    description,
    location,
    status,
    start_time,
    end_time,
    is_all_day,
    is_recurring
FROM {{ ref('google_calendar_events_normalized') }}
WHERE start_time IS NOT NULL
