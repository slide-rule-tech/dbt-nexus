{{ config(
    enabled=var('nexus', {}).get('attribution_models', {}).get('last_ttclid', {}).get('enabled', false),
    materialized='table', 
    tags=['attribution', 'ttclid', 'template-attribution-model']
) }}

{#
This model finds the last ttclid for each batch by looking back through 
the person's touchpoint history. For each batch, it identifies the most 
recent previous batch (for the same person) that contains a ttclid value.

The approach uses a window function to find the most recent previous batch with ttclid
for each person, then assigns that ttclid to all subsequent batches until 
a new ttclid is encountered.
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
        ttclid,
        row_number() over (
            partition by entity_id, entity_type 
            order by touchpoint_occurred_at
        ) as batch_sequence
    from touchpoint_batches
),

-- Use window function to carry forward the last ttclid for each entity
last_ttclid_attribution as (
    select
        touchpoint_batch_id,
        entity_id,
        entity_type,
        touchpoint_occurred_at,
        touchpoint_event_id,
        ttclid,
        -- Carry forward the last non-null ttclid for this entity
        last_value(ttclid ignore nulls) over (
            partition by entity_id, entity_type 
            order by touchpoint_occurred_at
            rows between unbounded preceding and current row
        ) as last_ttclid
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
        {{ nexus.create_nexus_id('attribution_model_result', ['lt.touchpoint_batch_id', 'tp.event_id', 'lt.entity_id', 'lt.entity_type']) }} as attribution_model_result_id,
        lt.touchpoint_occurred_at,
        'last_ttclid' as attribution_model_name,
        lt.touchpoint_batch_id,
        lt.touchpoint_event_id,
        tp.event_id as attributed_event_id,
        lt.entity_id,
        lt.entity_type,
        tp.event_occurred_at as attributed_event_occurred_at,
        lt.last_ttclid as ttclid
    from last_ttclid_attribution lt
    inner join touchpoint_paths tp
        on lt.touchpoint_batch_id = tp.touchpoint_batch_id
        and lt.entity_id = tp.entity_id
        and lt.entity_type = tp.entity_type
)

select * from final_output
where ttclid is not null
order by entity_id, entity_type, touchpoint_occurred_at, attributed_event_id
