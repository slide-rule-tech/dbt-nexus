{{ config(
    materialized=nexus.nexus_incremental_materialization(),
    on_schema_change='append_new_columns',
    tags=['identity-resolution', 'event-processing', 'entities']
) }}

{{ nexus.process_entity_identifiers() }}
