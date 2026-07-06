{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['entity_trait_id']),
    unique_key='entity_trait_id',
    on_schema_change='append_new_columns',
    tags=['nexus', 'entity_traits', 'gmail']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'entity_trait_id']) }}

-- Union all person and group traits using dbt_utils for column handling
WITH unioned_traits AS (
    {{ dbt_utils.union_relations(
        relations=[
            ref('gmail_message_person_traits'),
            ref('gmail_message_group_traits')
        ]
    ) }}
)

-- Deduplicate by entity_trait_id, keeping the most recent record.
-- Incremental mode: the QUALIFY dedups within the batch; the merge on
-- entity_trait_id keeps last-write-wins semantics across batches.
SELECT DISTINCT
    entity_trait_id,
    event_id,
    entity_type,
    identifier_type,
    identifier_value,
    trait_name,
    trait_value,
    source,
    occurred_at,
    _ingested_at
FROM unioned_traits
{{ nexus.nexus_incremental_source_filter() }}
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY entity_trait_id
    ORDER BY occurred_at DESC, _ingested_at DESC
) = 1

