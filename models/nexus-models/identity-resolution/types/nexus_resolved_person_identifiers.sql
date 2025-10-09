{{ config(
    materialized='table', 
    tags=['identity-resolution', 'persons'],
) }}

-- Uses unified entity_identifiers_edges table, filters by entity_type='person' in the macro
{{ nexus.resolve_identifiers('person', 'nexus_entity_identifiers', 'nexus_entity_identifiers_edges', var('nexus_max_recursion')) }}