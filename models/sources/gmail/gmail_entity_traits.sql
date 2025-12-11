{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'entity_traits', 'gmail']
) }}

-- Union all person and group traits using dbt_utils for column handling
WITH unioned_traits AS (
    {{ dbt_utils.union_relations(
        relations=[
            ref('gmail_message_person_traits'),
            ref('gmail_message_group_traits')
        ]
    ) }}
)

-- Deduplicate by entity_trait_id, keeping the most recent record
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
FROM unioned_traits
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY entity_trait_id 
    ORDER BY occurred_at DESC, _ingested_at DESC
) = 1

ORDER BY occurred_at DESC

