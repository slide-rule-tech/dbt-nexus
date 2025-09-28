{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

WITH person_traits AS (
    SELECT 
        person_trait_id as entity_trait_id,
        event_id,
        identifier_value,
        identifier_type,
        trait_name,
        trait_value,
        'person' as entity_type,
        occurred_at,
        source
    FROM {{ ref('google_calendar_person_traits') }}
),

group_traits AS (
    SELECT 
        group_trait_id as entity_trait_id,
        event_id,
        identifier_value,
        identifier_type,
        trait_name,
        trait_value,
        'group' as entity_type,
        occurred_at,
        source
    FROM {{ ref('google_calendar_group_traits') }}
)

SELECT 
    entity_trait_id,
    entity_type,
    event_id,
    identifier_value,
    identifier_type,
    trait_name,
    trait_value,
    occurred_at,
    source
FROM person_traits
UNION ALL
SELECT 
    entity_trait_id,
    entity_type,
    event_id,
    identifier_value,
    identifier_type,
    trait_name,
    trait_value,
    occurred_at,
    source
FROM group_traits
ORDER BY occurred_at DESC
