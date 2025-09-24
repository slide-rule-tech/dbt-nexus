{{ config(materialized='table', tags=['attribution', 'touchpoint-paths']) }}

{# 
This model efficiently filters the final CTE from touchpoints_with_participants 
to get the latest touchpoint for each event, creating the foundation for attribution modeling.
Based on the schema design in exploration.md
#}

with touchpoints_with_events as (
    select 
        touchpoint_id,
        touchpoint_event_id,
        attribution_deduplication_key,
        occurred_at,
        person_id,
        event_id,
        event_occurred_at
    from {{ ref('nexus_events_with_touchpoints') }}
),

latest_touchpoints_per_event as (
    select
        touchpoint_id,
        touchpoint_event_id,
        attribution_deduplication_key,
        occurred_at,
        person_id,
        event_id,
        event_occurred_at,
        -- Use ROW_NUMBER to efficiently get the latest touchpoint per event
        row_number() over (
            partition by event_id, person_id 
            order by occurred_at desc
        ) as touchpoint_rank
    from touchpoints_with_events
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['event_id', 'person_id', 'touchpoint_id']) }} as touchpoint_path_id,
        touchpoint_id as last_touchpoint_id,
        event_id,
        person_id,
        touchpoint_event_id,
        attribution_deduplication_key,
        occurred_at as touchpoint_occurred_at,
        event_occurred_at
    from latest_touchpoints_per_event
    where touchpoint_rank = 1
)

select * from final
