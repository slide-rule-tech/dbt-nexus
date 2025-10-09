{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'person_traits']
) }}

-- Extract person traits from Google Calendar events
WITH google_calendar_event_events AS (
    SELECT * FROM {{ ref('google_calendar_event_events') }}
),

organizer_traits AS (
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'organizer.email', "'person'", "'name'", "'organizer'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        organizer.email as identifier_value,
        'name' as trait_name,
        organizer.name as trait_value,
        'organizer' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events
    WHERE organizer.email IS NOT NULL AND organizer.name IS NOT NULL
    UNION ALL
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'organizer.email', "'person'", "'email'", "'organizer'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        organizer.email as identifier_value,
        'email' as trait_name,
        organizer.email as trait_value,
        'organizer' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events
    WHERE organizer.email IS NOT NULL
),

creator_traits AS (
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'creator.email', "'person'", "'name'", "'creator'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        creator.email as identifier_value,
        'name' as trait_name,
        creator.name as trait_value,
        'creator' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events
    WHERE creator.email IS NOT NULL AND creator.name IS NOT NULL
    UNION ALL
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'creator.email', "'person'", "'email'", "'creator'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        creator.email as identifier_value,
        'email' as trait_name,
        creator.email as trait_value,
        'creator' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events
    WHERE creator.email IS NOT NULL
),

attendee_traits AS (
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'attendee.email', "'person'", "'name'", "'attendee'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        attendee.email as identifier_value,
        'name' as trait_name,
        attendee.name as trait_value,
        'attendee' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events,
    UNNEST(attendees) as attendee
    WHERE attendee.email IS NOT NULL AND attendee.name IS NOT NULL
    UNION ALL
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'attendee.email', "'person'", "'email'", "'attendee'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        attendee.email as identifier_value,
        'email' as trait_name,
        attendee.email as trait_value,
        'attendee' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events,
    UNNEST(attendees) as attendee
    WHERE attendee.email IS NOT NULL
),

-- Deduplicate in case attendees array has duplicates
deduplicated AS (
    SELECT DISTINCT
        entity_trait_id,
        event_id,
        entity_type,
        identifier_type,
        identifier_value,
        trait_name,
        trait_value,
        role,
        source,
        occurred_at,
        _ingested_at
    FROM (
        SELECT * FROM organizer_traits
        UNION ALL
        SELECT * FROM creator_traits
        UNION ALL
        SELECT * FROM attendee_traits
    )
)

SELECT * FROM deduplicated
WHERE trait_value IS NOT NULL
ORDER BY occurred_at DESC

