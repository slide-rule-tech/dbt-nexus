{{ config(
    enabled=var('nexus', {}).get('attribution_models', {}).get('first_marketing_touch', {}).get('enabled', false),
    materialized='table', 
    tags=['attribution', 'marketing', 'template-attribution-model']
) }}

{#
This model provides first-touch marketing attribution. It identifies the earliest 
touchpoint for each person and attributes all subsequent events to that first 
touchpoint, regardless of the attribution window.

The key difference from last-touch attribution is that this model:
1. Finds the first touchpoint for each person (no time limit)
2. Attributes ALL subsequent events to that first touchpoint
3. Only requires that the event occurs AFTER the first touchpoint
#}

with touchpoint_batches as (
    select * from {{ ref('nexus_touchpoint_path_batches') }}
    where entity_type = 'person'  -- Filter for person entities only
),

-- Filter for web marketing touchpoints only
web_touchpoints as (
    select
        touchpoint_batch_id,
        entity_id,
        touchpoint_occurred_at,
        touchpoint_event_id,
        -- Attribution fields (already cleaned in source touchpoints)
        source,
        medium,
        campaign,
        content,
        gclid,
        touchpoint_type
    from touchpoint_batches
    where touchpoint_type = 'web'
),

-- Identify the first touchpoint for each person
first_touchpoints as (
    select
        entity_id,
        min(touchpoint_occurred_at) as first_touchpoint_occurred_at
    from web_touchpoints
    group by entity_id
),

-- Get the complete first touchpoint record for each person
first_touchpoint_details as (
    select
        wt.touchpoint_batch_id,
        wt.entity_id,
        wt.touchpoint_occurred_at,
        wt.touchpoint_event_id,
        wt.source,
        wt.medium,
        wt.campaign,
        wt.content,
        wt.gclid,
        wt.touchpoint_type
    from web_touchpoints wt
    inner join first_touchpoints ft
        on wt.entity_id = ft.entity_id
        and wt.touchpoint_occurred_at = ft.first_touchpoint_occurred_at
),

-- Get all events for persons who have first touchpoints
person_events as (
    select
        pp.entity_id,
        pp.entity_participant_id,
        e.event_id,
        e.occurred_at as event_occurred_at
    from {{ ref('nexus_entity_participants') }} pp
    inner join {{ ref('nexus_events') }} e
        on pp.event_id = e.event_id
    inner join first_touchpoint_details ftd
        on pp.entity_id = ftd.entity_id
    where pp.entity_type = 'person'  -- Filter for person entities only
),

-- Final output: attribute all events to first touchpoint if event occurs after touchpoint
final_output as (
    select
        {{ nexus.create_nexus_id('attribution_model_result', ['ftd.touchpoint_batch_id', 'pe.event_id', 'ftd.entity_id']) }} as attribution_model_result_id,
        ftd.touchpoint_occurred_at,
        'first_marketing_touch' as attribution_model_name,
        ftd.touchpoint_batch_id,
        ftd.touchpoint_event_id,
        pe.event_id as attributed_event_id,
        ftd.entity_id,
        pe.entity_participant_id,
        pe.event_occurred_at as attributed_event_occurred_at,
        -- Marketing attribution fields from the first touchpoint
        ftd.source,
        ftd.medium,
        ftd.campaign,
        ftd.content,
        ftd.gclid
    from first_touchpoint_details ftd
    inner join person_events pe
        on ftd.entity_id = pe.entity_id
        and pe.event_occurred_at >= ftd.touchpoint_occurred_at  -- Event must occur after first touchpoint
)

select * from final_output
order by entity_id, touchpoint_occurred_at, attributed_event_id
