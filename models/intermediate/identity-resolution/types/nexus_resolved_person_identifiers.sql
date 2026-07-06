{{ config(
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('resolved_at_watermark', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['identifier_type', 'identifier_value']),
    unique_key=['identifier_type', 'identifier_value'],
    on_schema_change='append_new_columns',
    tags=['identity-resolution', 'persons'],
) }}

{# Uses the unified entity_identifiers/edges tables, filtered to
   entity_type='person' inside the macros.

   Full path (table mode, first incremental run, --full-refresh): whole-graph
   traversal; entity ids are content-derived from each component's
   lexicographically-first identifier.

   Incremental path: contraction over the batch delta reading prior state
   from {{ this }}; existing entities keep their ids, merges re-point the
   losing entity's rows to the survivor. See
   docs/incremental-identity-resolution.md. #}
{{ nexus.nexus_incremental_upgrade_guard(['resolved_at_watermark', 'resolution_reason', 'previous_entity_id']) }}
{% if is_incremental() %}
{{ nexus.incremental_resolve_identifiers('person', 'nexus_entity_identifiers', 'nexus_entity_identifiers_edges', var('nexus', {}).get('max_recursion') or var('nexus_max_recursion', 5)) }}
{% else %}
{# Support both new unified config and legacy variable #}
{{ nexus.resolve_identifiers('person', 'nexus_entity_identifiers', 'nexus_entity_identifiers_edges', var('nexus', {}).get('max_recursion') or var('nexus_max_recursion', 10)) }}
{% endif %}
