{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'person_traits']
) }}

-- Extract person traits from google calendar event participants
WITH participants AS (
    SELECT * FROM {{ ref('google_calendar_event_participants') }}
),

participants_with_event_id AS (
    SELECT 
        {{ nexus.create_nexus_id('event', ['event_id']) }} as nexus_event_id,
        event_id,
        email,
        name,
        start_time,
        _ingested_at,
        role
    FROM participants
),

name_traits AS (
    -- Person name trait
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['nexus_event_id', 'email', "'person'", "'name'", 'role']) }} as entity_trait_id,
        nexus_event_id as event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'name' as trait_name,
        name as trait_value,
        'google_calendar' as source,
        start_time as occurred_at,
        _ingested_at
    FROM participants_with_event_id
    WHERE name IS NOT NULL

    UNION ALL

    -- Person email trait
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['nexus_event_id', 'email', "'person'", "'email'", 'role']) }} as entity_trait_id,
        nexus_event_id as event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'email' as trait_name,
        email as trait_value,
        'google_calendar' as source,
        start_time as occurred_at,
        _ingested_at
    FROM participants_with_event_id
    WHERE email IS NOT NULL
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
        source,
        occurred_at,
        _ingested_at
    FROM name_traits
)

SELECT * FROM deduplicated
ORDER BY occurred_at DESC
