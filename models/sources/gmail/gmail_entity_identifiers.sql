{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    unique_key='entity_identifier_id',
    on_schema_change='append_new_columns',
    tags=['nexus', 'entity_identifiers', 'gmail']
) }}

-- Union all person and group identifiers using dbt_utils for column handling
--
-- Incremental mode (nexus.incremental.enabled): append rows past this
-- model's own ingestion high-water mark, merging on entity_identifier_id so
-- re-ingested messages don't duplicate identifier occurrences.
select * from (
    {{ dbt_utils.union_relations(
        relations=[
            ref('gmail_message_person_identifiers'),
            ref('gmail_message_group_identifiers'),
            ref('gmail_thread_person_identifiers'),
            ref('gmail_thread_group_identifiers')
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
order by occurred_at desc
