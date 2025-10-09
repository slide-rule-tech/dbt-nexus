{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime', 'intermediate-layer']
) }}

-- Intermediate layer: Group identifiers for Google Calendar events
-- This layer extracts and standardizes group identifier fields using Nexus macros

WITH organizer_domains AS (
    SELECT 
        'organizer_domain' as role,
        {{ create_nexus_id('group_identifier', ['nexus_event_id', 'organizer.domain', "'organizer_domain'", 'start_time']) }} as group_identifier_id,
        nexus_event_id as event_id,
        {{ create_nexus_id('group_edge', ['nexus_event_id', 'organizer.domain']) }} as edge_id,
        organizer.domain as identifier_value,
        'domain' as identifier_type,
        'google_calendar' as source,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_normalized') }}
    WHERE {{ filter_non_generic_domains('organizer.domain') }}
),

creator_domains AS (
    SELECT 
        'creator_domain' as role,
        {{ create_nexus_id('group_identifier', ['nexus_event_id', 'creator.domain', "'creator_domain'", 'start_time']) }} as group_identifier_id,
        nexus_event_id as event_id,
        {{ create_nexus_id('group_edge', ['nexus_event_id', 'creator.domain']) }} as edge_id,
        creator.domain as identifier_value,
        'domain' as identifier_type,
        'google_calendar' as source,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_normalized') }}
    WHERE {{ filter_non_generic_domains('creator.domain') }}
),

attendee_domains AS (
    SELECT
        CASE 
            WHEN attendee.is_optional = true THEN 'optional_attendee_domain'
            ELSE 'attendee_domain'
        END as role,
        {{ create_nexus_id('group_identifier', ['base.nexus_event_id', 'attendee.domain', 'CASE WHEN attendee.is_optional = true THEN "optional_attendee_domain" ELSE "attendee_domain" END', 'base.start_time']) }} as group_identifier_id,
        base.nexus_event_id as event_id,
        {{ create_nexus_id('group_edge', ['base.nexus_event_id', 'attendee.domain']) }} as edge_id,
        attendee.domain as identifier_value,
        'domain' as identifier_type,
        'google_calendar' as source,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_normalized') }} base,
    UNNEST(base.attendees) as attendee
    WHERE {{ filter_non_generic_domains('attendee.domain') }}
    GROUP BY base.nexus_event_id, attendee.domain, attendee.is_optional, base.start_time
),

all_domains AS (
    SELECT * FROM organizer_domains
    UNION ALL
    SELECT * FROM creator_domains
    UNION ALL  
    SELECT * FROM attendee_domains
)

SELECT 
    group_identifier_id,
    event_id,
    edge_id,
    identifier_type,
    identifier_value,
    role,
    occurred_at,
    source
FROM all_domains
ORDER BY event_id DESC
