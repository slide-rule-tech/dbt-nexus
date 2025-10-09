{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'normalized']
) }}

SELECT
    nexus_event_id,
    calendar_event_id,
    summary,
    description,
    location,
    status,
    start_time,
    end_time,
    is_all_day,
    organizer,
    creator,
    attendees,
    has_external_attendees,
    source,
    event_name,
    event_description,
    synced_at
FROM {{ ref('google_calendar_events_base') }}

