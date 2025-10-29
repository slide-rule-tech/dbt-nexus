{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'person_identifiers']
) }}

-- Extract person identifiers from google calendar event participants
WITH participants AS (
    SELECT * FROM {{ ref('google_calendar_event_participants') }}
),

participants_with_event_id AS (
    SELECT 
        {{ nexus.create_nexus_id('event', ['calendar_event_id', 'start_time']) }} as event_id,
        calendar_event_id,
        email,
        start_time,
        _ingested_at,
        role
    FROM participants
    WHERE email IS NOT NULL
),

identifiers AS (
    SELECT 
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'email', "'person'", 'role']) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'google_calendar' as source,
        start_time as occurred_at,
        _ingested_at,
        role
    FROM participants_with_event_id
),

-- Deduplicate in case same person appears multiple times in same event
deduplicated AS (
    SELECT DISTINCT
        entity_identifier_id,
        event_id,
        edge_id,
        entity_type,
        identifier_type,
        identifier_value,
        source,
        occurred_at,
        _ingested_at,
        role
    FROM identifiers
)

SELECT * FROM deduplicated
WHERE identifier_value IS NOT NULL
ORDER BY occurred_at DESC
