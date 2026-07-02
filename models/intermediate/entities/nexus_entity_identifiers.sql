{{ config(
    materialized=nexus.nexus_incremental_materialization(),
    on_schema_change='append_new_columns',
    tags=['identity-resolution', 'event-processing', 'entities']
) }}

{# Append-only (no unique_key): running incrementally against a table built
   before the flag existed would silently duplicate every row. #}
{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at']) }}

{{ nexus.process_entity_identifiers() }}
