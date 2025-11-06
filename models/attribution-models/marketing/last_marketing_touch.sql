{{ config(
    enabled=var('nexus', {}).get('attribution_models', {}).get('last_marketing_touch', {}).get('enabled', true),
    materialized='table', 
    tags=['attribution', 'marketing', 'template-attribution-model']
) }}

{#
This model provides last-touch marketing attribution. It identifies the most recent
touchpoint for each person and attributes events to that last touchpoint, within
the attribution window.

The key difference from first-touch attribution is that this model:
1. Finds the last touchpoint for each person (within attribution window)
2. Attributes events to that most recent touchpoint
3. Only attributes events where touchpoint occurred before the event
#}

with touchpoint_batches as (
    select * from {{ ref('nexus_touchpoint_path_batches') }}
    where entity_type = 'person'  -- Filter for person entities only
),

-- Filter for web marketing touchpoints only
web_touchpoints as (
    select
        touchpoint_batch_id,
        entity_id as person_id,
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

-- Get all events for persons
person_events as (
    select
        pp.entity_id as person_id,
        e.event_id,
        e.occurred_at as event_occurred_at
    from {{ ref('nexus_entity_participants') }} pp
    inner join {{ ref('nexus_events') }} e
        on pp.event_id = e.event_id
    where pp.entity_type = 'person'  -- Filter for person entities only
),

-- Find the last touchpoint before each event
last_touchpoints as (
    select
        pe.person_id,
        pe.event_id,
        pe.event_occurred_at,
        wt.touchpoint_batch_id,
        wt.touchpoint_occurred_at,
        wt.touchpoint_event_id,
        wt.source,
        wt.medium,
        wt.campaign,
        wt.content,
        wt.gclid,
        row_number() over (
            partition by pe.event_id 
            order by wt.touchpoint_occurred_at desc
        ) as rn
    from person_events pe
    inner join web_touchpoints wt
        on pe.person_id = wt.person_id
        and wt.touchpoint_occurred_at <= pe.event_occurred_at  -- Touchpoint must occur before event
)

-- Final output: attribute events to last touchpoint
select
    {{ nexus.create_nexus_id('attribution_model_result', ['touchpoint_batch_id', 'event_id', 'person_id']) }} as attribution_model_result_id,
    touchpoint_occurred_at,
    'last_marketing_touch' as attribution_model_name,
    touchpoint_batch_id,
    touchpoint_event_id,
    event_id as attributed_event_id,
    person_id,
    event_occurred_at as attributed_event_occurred_at,
    -- Marketing attribution fields from the last touchpoint
    source,
    medium,
    campaign,
    content,
    gclid
from last_touchpoints
where rn = 1  -- Only get the most recent touchpoint per event
order by person_id, touchpoint_occurred_at, attributed_event_id

