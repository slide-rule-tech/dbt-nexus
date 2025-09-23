{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}
WITH organizer_memberships AS (
    SELECT 
        {{ create_nexus_id('membership_identifier', ['nexus_event_id', 'organizer.email', 'organizer.domain']) }} as membership_identifier_id,
        nexus_event_id as event_id,
        start_time as occurred_at,
        organizer.email as person_identifier,
        'email' as person_identifier_type,
        organizer.domain as group_identifier,
        'domain' as group_identifier_type,
        'organizer' as role,
        'google_calendar' as source
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
    AND organizer.domain IS NOT NULL
    AND organizer.domain != ''
),

creator_memberships AS (
    SELECT 
        {{ create_nexus_id('membership_identifier', ['nexus_event_id', 'creator.email', 'creator.domain']) }} as membership_identifier_id,
        nexus_event_id as event_id,
        start_time as occurred_at,
        creator.email as person_identifier,
        'email' as person_identifier_type,
        creator.domain as group_identifier,
        'domain' as group_identifier_type,
        'creator' as role,
        'google_calendar' as source
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
    AND creator.domain IS NOT NULL
    AND creator.domain != ''
),

attendee_memberships AS (
    SELECT
        {{ create_nexus_id('membership_identifier', ['base.nexus_event_id', 'attendee.email', 'attendee.domain']) }} as membership_identifier_id,
        base.nexus_event_id as event_id,
        base.start_time as occurred_at,
        attendee.email as person_identifier,
        'email' as person_identifier_type,
        attendee.domain as group_identifier,
        'domain' as group_identifier_type,
        'attendee' as role,
        'google_calendar' as source
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
    AND attendee.domain IS NOT NULL
    AND attendee.domain != ''
),

all_memberships AS (
    SELECT * FROM organizer_memberships
    UNION ALL
    SELECT * FROM creator_memberships
    UNION ALL
    SELECT * FROM attendee_memberships
)

SELECT 
    membership_identifier_id,
    event_id,
    occurred_at,
    person_identifier,
    person_identifier_type,
    group_identifier,
    group_identifier_type,
    role,
    source
FROM all_memberships
ORDER BY event_id DESC
