{{ config(
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['event_measurement_id']),
    unique_key='event_measurement_id',
    on_schema_change='append_new_columns'
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'event_measurement_id']) }}

-- Nexus Event Measurements
-- Unions all source-level event measurement models into a single table.
-- Each row represents a single quantitative observation extracted from an event.

{{ nexus.process_event_measurements() }}
