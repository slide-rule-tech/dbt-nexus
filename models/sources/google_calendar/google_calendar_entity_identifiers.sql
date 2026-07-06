{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['entity_identifier_id']),
    unique_key='entity_identifier_id',
    on_schema_change='append_new_columns',
    tags=['nexus', 'entity_identifiers', 'google_calendar']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'entity_identifier_id']) }}

-- Union all entity identifiers using dbt_utils for column handling
--
-- Incremental mode (nexus.incremental.enabled): append rows past this
-- model's own ingestion high-water mark, merging on entity_identifier_id.
-- The QUALIFY dedups the batch itself -- warehouse merges reject duplicate
-- keys within one batch.
select * from (
    {{ dbt_utils.union_relations(
        relations=[
            ref('google_calendar_person_identifiers'),
            ref('google_calendar_group_identifiers')
        ]
    ) }}
) unioned
{{ nexus.nexus_incremental_source_filter() }}
{% if is_incremental() %}
qualify row_number() over (
    partition by entity_identifier_id
    order by _ingested_at desc
) = 1
{% endif %}
