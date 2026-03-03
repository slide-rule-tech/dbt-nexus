{{ config(
    enabled=var('nexus', {}).get('attribution_models', {}).get('last_rdt_cid', {}).get('enabled', false),
    materialized='table',
    tags=['attribution', 'rdt_cid', 'template-attribution-model']
) }}

{#
This model finds the last Reddit click ID for each batch by looking back through
the entity's touchpoint history. For each batch, it identifies the most recent
previous batch (for the same entity) that contains an rdt_cid value.

The approach uses a window function to find the most recent previous batch with
rdt_cid for each entity, then assigns that value to all subsequent batches until
a new rdt_cid is encountered.
#}

with touchpoint_batches as (
    select * from {{ ref('nexus_touchpoint_path_batches') }}
),

entity_timeline as (
    select
        touchpoint_batch_id,
        entity_id,
        entity_type,
        touchpoint_occurred_at,
        touchpoint_event_id,
        case
            when landing_url like '%rdt_cid=%' then regexp_extract(landing_url, r'[\?&]rdt_cid=([^&]+)')
            when landing_url like '%rdclid=%' then regexp_extract(landing_url, r'[\?&]rdclid=([^&]+)')
            else null
        end as rdt_cid,
        row_number() over (
            partition by entity_id, entity_type
            order by touchpoint_occurred_at
        ) as batch_sequence
    from touchpoint_batches
),

last_rdt_cid_attribution as (
    select
        touchpoint_batch_id,
        entity_id,
        entity_type,
        touchpoint_occurred_at,
        touchpoint_event_id,
        rdt_cid,
        last_value(rdt_cid ignore nulls) over (
            partition by entity_id, entity_type
            order by touchpoint_occurred_at
            rows between unbounded preceding and current row
        ) as last_rdt_cid
    from entity_timeline
),

touchpoint_paths as (
    select
        touchpoint_batch_id,
        event_id,
        entity_id,
        entity_type,
        event_occurred_at
    from {{ ref('nexus_touchpoint_paths') }}
),

final_output as (
    select
        {{ nexus.create_nexus_id('attribution_model_result', ['lr.touchpoint_batch_id', 'tp.event_id', 'lr.entity_id', 'lr.entity_type']) }} as attribution_model_result_id,
        lr.touchpoint_occurred_at,
        'last_rdt_cid' as attribution_model_name,
        lr.touchpoint_batch_id,
        lr.touchpoint_event_id,
        tp.event_id as attributed_event_id,
        lr.entity_id,
        lr.entity_type,
        tp.event_occurred_at as attributed_event_occurred_at,
        lr.last_rdt_cid as rdt_cid
    from last_rdt_cid_attribution lr
    inner join touchpoint_paths tp
        on lr.touchpoint_batch_id = tp.touchpoint_batch_id
        and lr.entity_id = tp.entity_id
        and lr.entity_type = tp.entity_type
)

select * from final_output
where rdt_cid is not null
order by entity_id, entity_type, touchpoint_occurred_at, attributed_event_id
