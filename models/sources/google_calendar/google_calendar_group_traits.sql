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

all_traits AS (
    SELECT * FROM organizer_domain_traits
    UNION ALL
    SELECT * FROM creator_domain_traits
    UNION ALL
    SELECT * FROM attendee_domain_traits
)

SELECT DISTINCT
    event_id,
    identifier_value,
    identifier_type,
    trait_name,
    trait_value,
    occurred_at,
    'google-calendar' as source
FROM all_traits
WHERE identifier_value IS NOT NULL
ORDER BY occurred_at DESC
