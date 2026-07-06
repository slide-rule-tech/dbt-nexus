{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['event_id']),
    unique_key='event_id',
    on_schema_change='append_new_columns',
    tags=['nexus', 'events', 'google_calendar']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'event_id']) }}

-- Union all event types using dbt_utils for column handling
-- Future: add google_calendar_label_events if needed
--
-- Incremental mode (nexus.incremental.enabled): append rows past this
-- model's own ingestion high-water mark, merging on event_id. The QUALIFY
-- dedups the batch itself -- warehouse merges reject duplicate keys within
-- one batch (a re-synced record can appear twice in a lookback window).
select * from (
    {{ dbt_utils.union_relations(
        relations=[
            ref('google_calendar_event_events')
        ]
    ) }}
) unioned
{{ nexus.nexus_incremental_source_filter() }}
{% if is_incremental() %}
qualify row_number() over (
    partition by event_id
    order by _ingested_at desc
) = 1
{% endif %}
order by occurred_at desc
