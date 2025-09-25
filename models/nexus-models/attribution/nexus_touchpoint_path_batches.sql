{{ config(materialized='table', tags=['attribution', 'touchpoint-paths']) }}

{# 
This model creates deduplicated batches of touchpoint paths grouped by 
last_touchpoint_id + person_id for processing efficiency. 
Multiple events can share the same batch, as described in exploration.md
#}

with touchpoint_paths as (
    select * from {{ ref('nexus_touchpoint_paths') }}
),

batches as (
    select
        touchpoint_batch_id,
        max(last_touchpoint_id) as touchpoint_id,
        max(person_id) as person_id,
        min(touchpoint_occurred_at) as touchpoint_occurred_at,
        max(event_occurred_at) as last_event_occurred_at,
        count(*) as events_in_batch
    from touchpoint_paths
    group by touchpoint_batch_id
),

batches_with_attribution as (
    select
        b.touchpoint_batch_id,
        b.person_id,
        b.touchpoint_occurred_at,
        b.last_event_occurred_at,
        b.events_in_batch,
        -- Attribution columns from nexus_touchpoints
        t.*
    from batches b
    inner join {{ ref('nexus_touchpoints') }} t
        on b.touchpoint_id = t.touchpoint_id
)

select * from batches_with_attribution order by touchpoint_occurred_at desc
