{{ config(materialized='table') }}

SELECT DISTINCT
    relationship_type,
    entity_a_type,
    entity_b_type,
    relationship_direction
FROM {{ ref('nexus_relationships') }}
WHERE relationship_type IS NOT NULL
    AND entity_a_type IS NOT NULL
    AND entity_b_type IS NOT NULL
ORDER BY relationship_type, entity_a_type, entity_b_type

