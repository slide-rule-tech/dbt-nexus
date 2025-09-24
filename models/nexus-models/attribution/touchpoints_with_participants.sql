{{ config(materialized='table', tags=['attribution', 'touchpoint-paths']) }}
with touchpoints as (
    select 
        touchpoint_id, 
        touchpoint_event_id, 
        attribution_deduplication_key,
        occurred_at
    from {{ ref('nexus_touchpoints') }}
),

person_participants as (
    select event_id, person_id from {{ ref('nexus_person_participants') }}
),

events as (
    select 
        event_id,
        occurred_at as event_occurred_at
    from {{ ref('nexus_events') }}
),

events_with_participants as (
    select
        e.event_id,
        p.person_id,
        e.event_occurred_at
    from events e
    inner join person_participants p
        on e.event_id = p.event_id
),

touchpoints_with_participants as (
    select
        t.touchpoint_id,
        t.touchpoint_event_id,
        t.attribution_deduplication_key,
        t.occurred_at,
        p.person_id
    from touchpoints t
    inner join person_participants p
        on t.touchpoint_event_id = p.event_id
),

with_deduplicated_paths as (
    select
        *,
        case
            when lag(attribution_deduplication_key) over (
                partition by person_id 
                order by occurred_at
            ) = attribution_deduplication_key
            then true
            else false
        end as duplicate_touchpoint
        
    from touchpoints_with_participants
),

deduplicated_paths as (
    select * from with_deduplicated_paths
    where duplicate_touchpoint = false
),

touchpoints_with_events as (
    select
        t.touchpoint_id,
        t.touchpoint_event_id,
        t.attribution_deduplication_key,
        t.occurred_at,
        t.person_id,
        e.event_id,
        e.event_occurred_at
    from deduplicated_paths t
    inner join events_with_participants e
        on t.person_id = e.person_id
    where t.occurred_at < e.event_occurred_at
)

select * from touchpoints_with_events