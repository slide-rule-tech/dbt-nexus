{{ config(materialized='table', tags=['identity-resolution', 'entities']) }}

-- Optimized: Single join to all resolved identifiers instead of separate person/group joins + union
{{ nexus.resolve_entity_traits() }}

