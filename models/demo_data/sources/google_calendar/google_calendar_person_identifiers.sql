{{ config(
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

WITH organizer_identifiers AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.email as identifier_value,
        'email' as identifier_type
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
),

creator_identifiers AS (
    SELECT 
        nexus_event_id as event_id,
        creator.email as identifier_value,
        'email' as identifier_type
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
),

attendee_identifiers AS (
    SELECT
        base.nexus_event_id as event_id,  
        attendee.email as identifier_value,
        'email' as identifier_type
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
),

all_identifiers AS (
    SELECT * FROM organizer_identifiers
    UNION ALL
    SELECT * FROM creator_identifiers  
    UNION ALL
    SELECT * FROM attendee_identifiers
)

SELECT DISTINCT
    event_id,
    identifier_value,
    identifier_type
FROM all_identifiers