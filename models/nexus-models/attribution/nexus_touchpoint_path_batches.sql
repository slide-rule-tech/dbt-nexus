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
        {{ dbt_utils.generate_surrogate_key(['last_touchpoint_id', 'person_id']) }} as batch_id,
        last_touchpoint_id,
        person_id,
        min(touchpoint_occurred_at) as first_touchpoint_at,
        max(event_occurred_at) as last_event_at,
        count(*) as events_in_batch,
        count(distinct event_id) as unique_events_in_batch
    from touchpoint_paths
    group by last_touchpoint_id, person_id
)

select * from batches
