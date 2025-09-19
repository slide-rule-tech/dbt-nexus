{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}
WITH organizer_traits AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.email as identifier_value,
        'email' as identifier_type,
        'email' as trait_name,
        organizer.email as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
    
    UNION ALL
    
    SELECT 
        nexus_event_id as event_id,
        organizer.email as identifier_value,
        'email' as identifier_type,
        'name' as trait_name,
        organizer.name as trait_value,
        start_time as occurred_at
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
        creator.email as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
    
    UNION ALL
    
    SELECT 
        nexus_event_id as event_id,
        creator.email as identifier_value,
        'email' as identifier_type,
        'name' as trait_name,
        creator.name as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
    AND creator.name IS NOT NULL
    AND creator.name != ''
),

attendee_traits AS (
    SELECT
        base.nexus_event_id as event_id,
        attendee.email as identifier_value,
        'email' as identifier_type,
        'email' as trait_name,
        attendee.email as trait_value,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
    
    UNION ALL
    
    SELECT
        base.nexus_event_id as event_id,
        attendee.email as identifier_value,
        'email' as identifier_type,
        'name' as trait_name,
        attendee.name as trait_value,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
    AND attendee.name IS NOT NULL
    AND attendee.name != ''
),

-- Internal traits for organizers
organizer_internal_traits AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.email as identifier_value,
        'email' as identifier_type,
        'internal' as trait_name,
        CAST(false AS STRING) as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
),

-- Internal traits for creators
creator_internal_traits AS (
    SELECT 
        nexus_event_id as event_id,
        creator.email as identifier_value,
        'email' as identifier_type,
        'internal' as trait_name,
        CAST(false AS STRING) as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
),

-- Internal traits for attendees
attendee_internal_traits AS (
    SELECT
        base.nexus_event_id as event_id,
        attendee.email as identifier_value,
        'email' as identifier_type,
        'internal' as trait_name,
        CAST(false AS STRING) as trait_value,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
),

-- Test traits for organizers
organizer_test_traits AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.email as identifier_value,
        'email' as identifier_type,
        'test' as trait_name,
        CAST(false AS STRING) as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
),

-- Test traits for creators
creator_test_traits AS (
    SELECT 
        nexus_event_id as event_id,
        creator.email as identifier_value,
        'email' as identifier_type,
        'test' as trait_name,
        CAST(false AS STRING) as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
),

-- Test traits for attendees
attendee_test_traits AS (
    SELECT
        base.nexus_event_id as event_id,
        attendee.email as identifier_value,
        'email' as identifier_type,
        'test' as trait_name,
        CAST(false AS STRING) as trait_value,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
),

all_traits AS (
    SELECT * FROM organizer_traits
    UNION ALL
    SELECT * FROM creator_traits
    UNION ALL
    SELECT * FROM attendee_traits
    UNION ALL
    SELECT * FROM organizer_internal_traits
    UNION ALL
    SELECT * FROM creator_internal_traits
    UNION ALL
    SELECT * FROM attendee_internal_traits
    UNION ALL
    SELECT * FROM organizer_test_traits
    UNION ALL
    SELECT * FROM creator_test_traits
    UNION ALL
    SELECT * FROM attendee_test_traits
)

SELECT 
    event_id,
    {{ dbt_utils.generate_surrogate_key(['event_id', 'identifier_value', 'trait_name']) }} as row_id,
    identifier_type,
    identifier_value,
    trait_name,
    trait_value,
    occurred_at,
    'google-calendar' as source
FROM all_traits
WHERE identifier_value IS NOT NULL
ORDER BY event_id DESC