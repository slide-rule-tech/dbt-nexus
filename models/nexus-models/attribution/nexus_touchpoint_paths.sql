{{ config(materialized='table', tags=['attribution', 'touchpoint-paths']) }}

-- Nexus Touchpoint Paths
-- Links touchpoints with person participants to create attribution paths
-- Follows the attribution modeling schema from exploration.md

with touchpoints as (
    select * from {{ ref('nexus_touchpoints') }}
),

person_participants as (
    select * from {{ ref('nexus_person_participants') }}
),

events as (
    select * from {{ ref('nexus_events') }}
),

events_with_participants as (
    select
        e.event_id,
        p.person_id
    from events e
    inner join person_participants p
        on e.event_id = p.event_id
),

touchpoint_paths as (
    select
        -- Touchpoint path identification
        {{ nexus.create_nexus_id('touchpoint_path', ['t.touchpoint_id', 'pp.person_id']) }} as touchpoint_path_id,
        pp.person_id,
        t.*,
        
        -- Person context
        pp.person_participant_id,
        pp.role
        
    from touchpoints t
    inner join events_with_participants pp
        on t.touchpoint_event_id = pp.event_id
),

-- Deduplicate touchpoints: if attribution deduplication key is the same as previous touchpoint for same person, mark as duplicate
deduplicated_paths as (
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
        
    from touchpoint_paths
),

-- Filter out duplicate touchpoints
final as (
    select 
        *
    from deduplicated_paths
    where duplicate_touchpoint = false
)

select * from final
where person_id = 'per_aeef234cf389f72d0411a034499659ff'
order by touchpoint_id desc
