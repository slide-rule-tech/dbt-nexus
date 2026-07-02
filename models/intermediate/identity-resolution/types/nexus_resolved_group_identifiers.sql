{{ config(
    materialized=nexus.nexus_incremental_materialization(),
    unique_key=['identifier_type', 'identifier_value'],
    on_schema_change='append_new_columns',
    tags=['identity-resolution', 'groups'],
) }}

{# Uses the unified entity_identifiers/edges tables, filtered to
   entity_type='group' inside the macros. See
   nexus_resolved_person_identifiers.sql for the full/incremental split. #}
{% if is_incremental() %}
{{ nexus.incremental_resolve_identifiers('group', 'nexus_entity_identifiers', 'nexus_entity_identifiers_edges', var('nexus', {}).get('max_recursion') or var('nexus_max_recursion', 5)) }}
{% else %}
{# Support both new unified config and legacy variable #}
{{ resolve_identifiers('group', 'nexus_entity_identifiers', 'nexus_entity_identifiers_edges', var('nexus', {}).get('max_recursion') or var('nexus_max_recursion', 10)) }}
{% endif %}
