{{ config(materialized='table', tags=['attribution', 'touchpoint-paths']) }}

with touchpoint_paths as (
    select * from {{ ref('nexus_touchpoint_paths') }}
),
batches as (
    select
        touchpoint_batch_id,
        max(last_touchpoint_id) as touchpoint_id,
        max(entity_id) as entity_id,
        max(entity_type) as entity_type,
        min(touchpoint_occurred_at) as touchpoint_occurred_at,
        max(event_occurred_at) as last_event_occurred_at,
        count(*) as events_in_batch
    from touchpoint_paths
    group by touchpoint_batch_id
),
batches_with_attribution as (
    select 
        b.touchpoint_batch_id,
        b.entity_id,
        b.entity_type,
        b.touchpoint_occurred_at,
        b.last_event_occurred_at,
        b.events_in_batch,
        -- Attribution columns from nexus_touchpoints
        t.*
    from batches b
    inner join {{ ref('nexus_touchpoints') }} t on b.touchpoint_id = t.touchpoint_id
)
select * from batches_with_attribution order by touchpoint_occurred_at desc
