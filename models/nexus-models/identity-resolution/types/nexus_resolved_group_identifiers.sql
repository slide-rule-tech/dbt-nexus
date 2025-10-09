{{ config(
    materialized='table', 
    tags=['identity-resolution', 'groups'],
) }}

-- Uses unified entity_identifiers_edges table, filters by entity_type='group' in the macro
{# Support both new unified config and legacy variable #}
{{ resolve_identifiers('group', 'nexus_entity_identifiers', 'nexus_entity_identifiers_edges', var('nexus', {}).get('max_recursion') or var('nexus_max_recursion', 10)) }}


