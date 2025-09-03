{{ config(
    materialized='table',
    tags=['event-processing']
) }}

WITH organizer_traits AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.email as person_identifier,
        'email' as identifier_type,
        'email' as trait_name,
        organizer.email as trait_value
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
    
    UNION ALL
    
    SELECT 
        nexus_event_id as event_id,
        organizer.email as person_identifier,
        'email' as identifier_type,
        'display_name' as trait_name,
        organizer.name as trait_value
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
    AND organizer.name IS NOT NULL
    AND organizer.name != ''
),

creator_traits AS (
    SELECT 
        nexus_event_id as event_id,
        creator.email as person_identifier,
        'email' as identifier_type,
        'email' as trait_name,
        creator.email as trait_value
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
    
    UNION ALL
    
    SELECT 
        nexus_event_id as event_id,
        creator.email as person_identifier,
        'email' as identifier_type,
        'display_name' as trait_name,
        creator.name as trait_value
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
    AND creator.name IS NOT NULL
    AND creator.name != ''
),

attendee_traits AS (
    SELECT
        base.nexus_event_id as event_id,
        attendee.email as person_identifier,
        'email' as identifier_type,
        'email' as trait_name,
        attendee.email as trait_value
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
    
    UNION ALL
    
    SELECT
        base.nexus_event_id as event_id,
        attendee.email as person_identifier,
        'email' as identifier_type,
        'display_name' as trait_name,
        attendee.name as trait_value
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
    AND attendee.name IS NOT NULL
    AND attendee.name != ''
),

all_traits AS (
    SELECT * FROM organizer_traits
    UNION ALL
    SELECT * FROM creator_traits
    UNION ALL
    SELECT * FROM attendee_traits
)

SELECT DISTINCT
    event_id,
    person_identifier,
    identifier_type,
    trait_name,
    trait_value
FROM all_traits