{{ config(
    materialized='table',
    tags=['event-processing']
) }}

WITH organizer_memberships AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.email as person_identifier,
        'email' as identifier_type
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
),

creator_memberships AS (
    SELECT 
        nexus_event_id as event_id,
        creator.email as person_identifier,
        'email' as identifier_type
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
),

attendee_memberships AS (
    SELECT
        base.nexus_event_id as event_id,
        attendee.email as person_identifier, 
        'email' as identifier_type
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
),

all_memberships AS (
    SELECT * FROM organizer_memberships
    UNION ALL
    SELECT * FROM creator_memberships
    UNION ALL
    SELECT * FROM attendee_memberships
)

SELECT DISTINCT
    event_id,
    person_identifier,
    identifier_type
FROM all_memberships