{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    unique_key='event_id',
    on_schema_change='append_new_columns',
    tags=['nexus', 'events', 'gmail']
) }}

-- Union all event types using dbt_utils for column handling
-- Future: add gmail_label_events, gmail_thread_events
--
-- Incremental mode (nexus.incremental.enabled): append rows past this
-- model's own ingestion high-water mark; a re-synced message (same event_id,
-- new _ingested_at) merge-overwrites its previous row.
select * from (
    {{ dbt_utils.union_relations(
        relations=[
            ref('gmail_message_events'),
            ref('gmail_thread_events')
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
