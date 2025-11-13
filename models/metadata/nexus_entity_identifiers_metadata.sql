{{ config(materialized='table') }}

SELECT DISTINCT
    entity_type,
    identifier_type
FROM {{ ref('nexus_entity_identifiers') }}
WHERE entity_type IS NOT NULL
    AND identifier_type IS NOT NULL
ORDER BY entity_type, identifier_type

