{{ config(
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['entity_identifier_id']),
    unique_key='entity_identifier_id',
    on_schema_change='append_new_columns',
    tags=['identity-resolution', 'event-processing', 'entities']
) }}

{# unique_key: identifier occurrences are immutable facts keyed by
   entity_identifier_id, so re-emissions from upstream (a source refreshing a
   row's _ingested_at, lookback reprocessing) merge instead of duplicating.
   Found the hard way: a source model stamping _ingested_at with now() made
   its rows look new every run and this table appended them every run. #}
{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at']) }}

{{ nexus.process_entity_identifiers() }}
