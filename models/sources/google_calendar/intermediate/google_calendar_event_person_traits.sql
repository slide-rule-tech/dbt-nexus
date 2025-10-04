{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime', 'intermediate-layer']
) }}

-- Intermediate layer: Person traits for Google Calendar events
-- This layer extracts and standardizes person trait/attribute fields using Nexus macros

WITH organizer_traits AS (
    SELECT 
        {{ create_nexus_id('person_trait', ['nexus_event_id', 'organizer.email', "'email'", "'organizer'"]) }} as person_trait_id,
        nexus_event_id as event_id,
        organizer.email as identifier_value,
        'email' as identifier_type,
        'email' as trait_name,
        organizer.email as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_normalized') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
    
    UNION ALL
    
    SELECT 
        {{ create_nexus_id('person_trait', ['nexus_event_id', 'organizer.email', "'name'", "'organizer'"]) }} as person_trait_id,
        nexus_event_id as event_id,
        organizer.email as identifier_value,
        'email' as identifier_type,
        'name' as trait_name,
        organizer.name as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_normalized') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
    AND organizer.name IS NOT NULL
    AND organizer.name != ''
),

creator_traits AS (
    SELECT 
        {{ create_nexus_id('person_trait', ['nexus_event_id', 'creator.email', "'email'", "'creator'"]) }} as person_trait_id,
        nexus_event_id as event_id,
        creator.email as person_identifier,
        'email' as identifier_type,
        'email' as trait_name,
        creator.email as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_normalized') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
    
    UNION ALL
    
    SELECT 
        {{ create_nexus_id('person_trait', ['nexus_event_id', 'creator.email', "'name'", "'creator'"]) }} as person_trait_id,
        nexus_event_id as event_id,
        creator.email as identifier_value,
        'email' as identifier_type,
        'name' as trait_name,
        creator.name as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_normalized') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
    AND creator.name IS NOT NULL
    AND creator.name != ''
),

attendee_traits AS (
    SELECT
        {{ create_nexus_id('person_trait', ['base.nexus_event_id', 'attendee.email', "'email'", "'attendee'"]) }} as person_trait_id,
        base.nexus_event_id as event_id,
        attendee.email as identifier_value,
        'email' as identifier_type,
        'email' as trait_name,
        attendee.email as trait_value,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_normalized') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
    
    UNION ALL
    
    SELECT
        {{ create_nexus_id('person_trait', ['base.nexus_event_id', 'attendee.email', "'name'", "'attendee'"]) }} as person_trait_id,
        base.nexus_event_id as event_id,
        attendee.email as identifier_value,
        'email' as identifier_type,
        'name' as trait_name,
        attendee.name as trait_value,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_normalized') }} base,
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
    person_trait_id,
    event_id,
    identifier_value,
    identifier_type,
    trait_name,
    trait_value,
    occurred_at,
    'google-calendar' as source
FROM all_traits
where identifier_value is not null
order by occurred_at desc
