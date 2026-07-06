{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    unique_key='relationship_declaration_id',
    on_schema_change='append_new_columns',
    tags=['nexus', 'relationship_declarations', 'gmail']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'relationship_declaration_id']) }}

-- Union all relationship declarations using dbt_utils for column handling
-- Future: add gmail_label_relationships, gmail_thread_relationships
--
-- Incremental mode (nexus.incremental.enabled): append rows past this
-- model's own ingestion high-water mark, merging on
-- relationship_declaration_id.
select * from (
    {{ dbt_utils.union_relations(
        relations=[
            ref('gmail_message_relationship_declarations')
        ]
    ) }}
) unioned
{{ nexus.nexus_incremental_source_filter() }}
{% if is_incremental() %}
qualify row_number() over (
    partition by relationship_declaration_id
    order by _ingested_at desc
) = 1
{% endif %}
order by occurred_at desc
