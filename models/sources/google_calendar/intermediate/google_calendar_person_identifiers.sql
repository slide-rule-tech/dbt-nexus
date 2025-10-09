{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'person_identifiers']
) }}

-- Extract person identifiers from Google Calendar events
WITH google_calendar_event_events AS (
    SELECT * FROM {{ ref('google_calendar_event_events') }}
),

organizer_identifiers AS (
    SELECT 
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'organizer.email', "'person'", "'organizer'"]) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'person' as entity_type,
        'email' as identifier_type,
        organizer.email as identifier_value,
        'organizer' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
),

creator_identifiers AS (
    SELECT 
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'creator.email', "'person'", "'creator'"]) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'person' as entity_type,
        'email' as identifier_type,
        creator.email as identifier_value,
        'creator' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
),

attendee_identifiers AS (
    SELECT
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'attendee.email', "'person'", "'attendee'"]) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'person' as entity_type,
        'email' as identifier_type,
        attendee.email as identifier_value,
        'attendee' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events,
    UNNEST(attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
),

-- Deduplicate in case attendees array has duplicates
deduplicated AS (
    SELECT DISTINCT
        entity_identifier_id,
        event_id,
        edge_id,
        entity_type,
        identifier_type,
        identifier_value,
        role,
        source,
        occurred_at,
        _ingested_at
    FROM (
        SELECT * FROM organizer_identifiers
        UNION ALL
        SELECT * FROM creator_identifiers
        UNION ALL
        SELECT * FROM attendee_identifiers
    )
)

SELECT * FROM deduplicated
WHERE identifier_value IS NOT NULL
ORDER BY occurred_at DESC

