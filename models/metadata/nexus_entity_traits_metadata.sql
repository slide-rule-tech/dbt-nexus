{{ config(materialized='table') }}

SELECT DISTINCT
    entity_type,
    trait_name
FROM {{ ref('nexus_entity_traits') }}
WHERE entity_type IS NOT NULL
    AND trait_name IS NOT NULL
ORDER BY entity_type, trait_name

