{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    unique_key='entity_trait_id',
    on_schema_change='append_new_columns',
    tags=['nexus', 'entity_traits', 'google_calendar']
) }}

-- Union all entity traits using dbt_utils for column handling
--
-- Incremental mode (nexus.incremental.enabled): append rows past this
-- model's own ingestion high-water mark, merging on entity_trait_id. The
-- QUALIFY dedups the batch itself -- warehouse merges reject duplicate keys
-- within one batch.
select * from (
    {{ dbt_utils.union_relations(
        relations=[
            ref('google_calendar_person_traits'),
            ref('google_calendar_group_traits')
        ]
    ) }}
) unioned
{{ nexus.nexus_incremental_source_filter() }}
{% if is_incremental() %}
qualify row_number() over (
    partition by entity_trait_id
    order by occurred_at desc, _ingested_at desc
) = 1
{% endif %}
order by occurred_at desc
