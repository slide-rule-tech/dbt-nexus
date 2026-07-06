{{ config(
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['edge_uniqueness_hash']),
    unique_key='edge_uniqueness_hash',
    on_schema_change='append_new_columns',
    tags=['identity-resolution', 'entities']
) }}

{# Pre-incremental edge tables lack the hash the merge matches on, so rows
   would duplicate instead of merging. #}
{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'edge_uniqueness_hash']) }}

{{ nexus.create_identifier_edges('nexus_entity_identifiers') }}
