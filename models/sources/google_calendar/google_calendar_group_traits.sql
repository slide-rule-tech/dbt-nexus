{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

WITH organizer_domain_traits AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.domain as identifier_value,
        'domain' as identifier_type,
        'domain' as trait_name,
        organizer.domain as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE {{ filter_non_generic_domains('organizer.domain') }}
),

creator_domain_traits AS (
    SELECT 
        nexus_event_id as event_id,
        creator.domain as identifier_value,
        'domain' as identifier_type,
        'domain' as trait_name,
        creator.domain as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE {{ filter_non_generic_domains('creator.domain') }}
),

attendee_domain_traits AS (
    SELECT
        base.nexus_event_id as event_id,
        attendee.domain as identifier_value,
        'domain' as identifier_type,
        'domain' as trait_name,
        attendee.domain as trait_value,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE {{ filter_non_generic_domains('attendee.domain') }}
),

-- Internal traits for organizers
organizer_internal_traits AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.domain as identifier_value,
        'domain' as identifier_type,
        'internal' as trait_name,
        CAST(false AS STRING) as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE {{ filter_non_generic_domains('organizer.domain') }}
),

-- Internal traits for creators
creator_internal_traits AS (
    SELECT 
        nexus_event_id as event_id,
        creator.domain as identifier_value,
        'domain' as identifier_type,
        'internal' as trait_name,
        CAST(false AS STRING) as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE {{ filter_non_generic_domains('creator.domain') }}
),

-- Internal traits for attendees
attendee_internal_traits AS (
    SELECT
        base.nexus_event_id as event_id,
        attendee.domain as identifier_value,
        'domain' as identifier_type,
        'internal' as trait_name,
        CAST(false AS STRING) as trait_value,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE {{ filter_non_generic_domains('attendee.domain') }}
),

-- Test traits for organizers
organizer_test_traits AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.domain as identifier_value,
        'domain' as identifier_type,
        'test' as trait_name,
        CAST(false AS STRING) as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE {{ filter_non_generic_domains('organizer.domain') }}
),

-- Test traits for creators
creator_test_traits AS (
    SELECT 
        nexus_event_id as event_id,
        creator.domain as identifier_value,
        'domain' as identifier_type,
        'test' as trait_name,
        CAST(false AS STRING) as trait_value,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE {{ filter_non_generic_domains('creator.domain') }}
),

-- Test traits for attendees
attendee_test_traits AS (
    SELECT
        base.nexus_event_id as event_id,
        attendee.domain as identifier_value,
        'domain' as identifier_type,
        'test' as trait_name,
        CAST(false AS STRING) as trait_value,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE {{ filter_non_generic_domains('attendee.domain') }}
),

all_traits AS (
    SELECT * FROM organizer_domain_traits
    UNION ALL
    SELECT * FROM creator_domain_traits
    UNION ALL
    SELECT * FROM attendee_domain_traits
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
