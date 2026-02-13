{{ config(
    enabled=var('nexus', {}).get('attribution_models', {}).get('last_li_fat_id', {}).get('enabled', false),
    materialized='table', 
    tags=['attribution', 'li_fat_id', 'template-attribution-model']
) }}

{#
This model finds the last li_fat_id for each batch by looking back through 
the person's touchpoint history. For each batch, it identifies the most 
recent previous batch (for the same person) that contains a li_fat_id value.

The approach uses a window function to find the most recent previous batch with li_fat_id
for each person, then assigns that li_fat_id to all subsequent batches until 
a new li_fat_id is encountered.
#}

with touchpoint_batches as (
    select * from {{ ref('nexus_touchpoint_path_batches') }}
),

-- Create a complete timeline for each entity with all batches
entity_timeline as (
    select
        touchpoint_batch_id,
        entity_id,
        entity_type,
        touchpoint_occurred_at,
        touchpoint_event_id,
        li_fat_id,
        row_number() over (
            partition by entity_id, entity_type 
            order by touchpoint_occurred_at
        ) as batch_sequence
    from touchpoint_batches
),

-- Use window function to carry forward the last li_fat_id for each entity
last_li_fat_id_attribution as (
    select
        touchpoint_batch_id,
        entity_id,
        entity_type,
        touchpoint_occurred_at,
        touchpoint_event_id,
        li_fat_id,
        -- Carry forward the last non-null li_fat_id for this entity
        last_value(li_fat_id ignore nulls) over (
            partition by entity_id, entity_type 
            order by touchpoint_occurred_at
            rows between unbounded preceding and current row
        ) as last_li_fat_id
    from entity_timeline
),

-- Join with nexus_touchpoint_paths to get all event_ids for each batch
touchpoint_paths as (
    select 
        touchpoint_batch_id,
        event_id,
        entity_id,
        entity_type,
        event_occurred_at
    from {{ ref('nexus_touchpoint_paths') }}
),

-- Final output: attribution model results with metadata
final_output as (
    select
        {{ nexus.create_nexus_id('attribution_model_result', ['ll.touchpoint_batch_id', 'tp.event_id', 'll.entity_id', 'll.entity_type']) }} as attribution_model_result_id,
        ll.touchpoint_occurred_at,
        'last_li_fat_id' as attribution_model_name,
        ll.touchpoint_batch_id,
        ll.touchpoint_event_id,
        tp.event_id as attributed_event_id,
        ll.entity_id,
        ll.entity_type,
        tp.event_occurred_at as attributed_event_occurred_at,
        ll.last_li_fat_id as li_fat_id
    from last_li_fat_id_attribution ll
    inner join touchpoint_paths tp
        on ll.touchpoint_batch_id = tp.touchpoint_batch_id
        and ll.entity_id = tp.entity_id
        and ll.entity_type = tp.entity_type
)

select * from final_output
where li_fat_id is not null
order by entity_id, entity_type, touchpoint_occurred_at, attributed_event_id
