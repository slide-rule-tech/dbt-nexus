{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

WITH person_identifiers AS (
    SELECT 
        person_identifier_id as entity_identifier_id,
        event_id,
        edge_id,
        identifier_type,
        identifier_value,
        role,
        'person' as entity_type,
        occurred_at,
        source
    FROM {{ ref('google_calendar_person_identifiers') }}
),

group_identifiers AS (
    SELECT 
        group_identifier_id as entity_identifier_id,
        event_id,
        edge_id,
        identifier_type,
        identifier_value,
        role,
        'group' as entity_type,
        occurred_at,
        source
    FROM {{ ref('google_calendar_group_identifiers') }}
)

SELECT 
    entity_identifier_id,
    entity_type,
    event_id,
    edge_id,
    identifier_type,
    identifier_value,
    role,
    occurred_at,
    source
FROM person_identifiers
UNION ALL
SELECT 
    entity_identifier_id,
    entity_type,
    event_id,
    edge_id,
    identifier_type,
    identifier_value,
    role,
    occurred_at,
    source
FROM group_identifiers
ORDER BY event_id DESC
