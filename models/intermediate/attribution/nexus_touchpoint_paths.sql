{{ config(materialized='table', tags=['attribution', 'touchpoint-paths']) }}

with touchpoints as (
    select touchpoint_id, touchpoint_event_id, attribution_deduplication_key, occurred_at
    from {{ ref('nexus_touchpoints') }}
),
entity_participants as (
    select event_id, entity_id, entity_type
    from {{ ref('nexus_entity_participants') }}
),
events as (
    select event_id, occurred_at as event_occurred_at
    from {{ ref('nexus_events') }}
),
events_with_participants as (
    select e.event_id, p.entity_id, p.entity_type, e.event_occurred_at
    from events e
    inner join entity_participants p on e.event_id = p.event_id
),
touchpoints_with_participants as (
    select t.touchpoint_id, t.touchpoint_event_id, t.attribution_deduplication_key,
           t.occurred_at, p.entity_id, p.entity_type
    from touchpoints t
    inner join entity_participants p on t.touchpoint_event_id = p.event_id
),
with_deduplicated_paths as (
    select *,
        case when lag(attribution_deduplication_key) over (
            partition by entity_id, entity_type order by occurred_at
        ) = attribution_deduplication_key then true else false end as duplicate_touchpoint
    from touchpoints_with_participants
),
deduplicated_paths as (
    select * from with_deduplicated_paths where duplicate_touchpoint = false
),
latest_touchpoint_times as (
    select e.event_id, e.entity_id, e.entity_type, e.event_occurred_at,
           max(t.occurred_at) as latest_touchpoint_at
    from events_with_participants e
    inner join deduplicated_paths t
        on e.entity_id = t.entity_id
        and e.entity_type = t.entity_type
        and t.occurred_at <= e.event_occurred_at
        and {{ dbt.datediff('t.occurred_at', 'e.event_occurred_at', 'day') }} <= 90
    group by e.event_id, e.entity_id, e.entity_type, e.event_occurred_at
),
touchpoints_with_events as (
    select t.touchpoint_id, t.touchpoint_event_id, t.attribution_deduplication_key,
           t.occurred_at, t.entity_id, t.entity_type, lt.event_id, lt.event_occurred_at,
           row_number() over (partition by lt.event_id order by t.touchpoint_id) as tie_breaker_rank
    from latest_touchpoint_times lt
    inner join deduplicated_paths t
        on lt.entity_id = t.entity_id 
        and lt.entity_type = t.entity_type 
        and lt.latest_touchpoint_at = t.occurred_at
),
final as (
    select
        {{ nexus.create_nexus_id('touchpoint_path', ['event_id', 'entity_id', 'entity_type', 'touchpoint_id']) }} as touchpoint_path_id,
        {{ nexus.create_nexus_id('touchpoint_path_batch', ['touchpoint_id', 'entity_id', 'entity_type']) }} as touchpoint_batch_id,
        touchpoint_id as last_touchpoint_id,
        event_id, entity_id, entity_type, touchpoint_event_id, attribution_deduplication_key,
        occurred_at as touchpoint_occurred_at,
        event_occurred_at
    from touchpoints_with_events
    where tie_breaker_rank = 1
)
select * from final
