{{ config(
    materialized=nexus.nexus_incremental_materialization(),
    unique_key='edge_uniqueness_hash',
    on_schema_change='append_new_columns',
    tags=['identity-resolution', 'entities']
) }}

{{ nexus.create_identifier_edges('nexus_entity_identifiers') }}
