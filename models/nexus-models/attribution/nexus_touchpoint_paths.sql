{{ config(materialized='table', tags=['attribution', 'touchpoint-paths']) }}

{# 
This model efficiently matches each event to its latest prior touchpoint within a 90-day attribution window.
Combines the logic from nexus_events_with_touchpoints and creates the final touchpoint path records.
Based on the schema design in exploration.md
#}

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

-- Step 1: Find the latest touchpoint timestamp for each event (with 90-day attribution window)
latest_touchpoint_times as (
    select 
        e.event_id,
        e.person_id,
        e.event_occurred_at,
        max(t.occurred_at) as latest_touchpoint_at
    from events_with_participants e
    inner join deduplicated_paths t 
        on e.person_id = t.person_id 
        and t.occurred_at <= e.event_occurred_at
        and datediff('day', t.occurred_at, e.event_occurred_at) <= 7  -- 90-day attribution window
    group by e.event_id, e.person_id, e.event_occurred_at
),

-- Step 2: Join back to get the actual touchpoint details with tie-breaker
touchpoints_with_events as (
    select
        t.touchpoint_id,
        t.touchpoint_event_id,
        t.attribution_deduplication_key,
        t.occurred_at,
        t.person_id,
        lt.event_id,
        lt.event_occurred_at,
        -- Add tie-breaker for multiple touchpoints at same timestamp
        row_number() over (
            partition by lt.event_id 
            order by t.touchpoint_id  -- Use touchpoint_id as deterministic tie-breaker
        ) as tie_breaker_rank
    from latest_touchpoint_times lt
    inner join deduplicated_paths t 
        on lt.person_id = t.person_id 
        and lt.latest_touchpoint_at = t.occurred_at
),

-- Step 3: Create final touchpoint paths with clean interface
final as (
    select
        {{ nexus.create_nexus_id('touchpoint_path', ['event_id', 'person_id', 'touchpoint_id']) }} as touchpoint_path_id,
        {{ nexus.create_nexus_id('touchpoint_path_batch', ['touchpoint_id', 'person_id']) }} as touchpoint_batch_id,
        touchpoint_id as last_touchpoint_id,
        event_id,
        person_id,
        touchpoint_event_id,
        attribution_deduplication_key,
        occurred_at as touchpoint_occurred_at,
        event_occurred_at
    from touchpoints_with_events
    where tie_breaker_rank = 1
)

select * from final
