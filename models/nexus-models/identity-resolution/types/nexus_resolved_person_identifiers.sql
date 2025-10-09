{{ config(
    materialized='table', 
    tags=['identity-resolution', 'persons'],
) }}

-- Uses unified entity_identifiers_edges table, filters by entity_type='person' in the macro
{# Support both new unified config and legacy variable #}
{{ nexus.resolve_identifiers('person', 'nexus_entity_identifiers', 'nexus_entity_identifiers_edges', var('nexus', {}).get('max_recursion') or var('nexus_max_recursion', 10)) }}