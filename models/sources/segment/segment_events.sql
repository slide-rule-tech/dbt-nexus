-- Nexus Segment Events - Touchpoint Filtered
-- Filters segment_all_events to only include events that exist as touchpoints
-- Joins with segment_touchpoints to ensure only attribution-relevant events are included

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'events', 'touchpoints'], 
    materialized='table'
) }}

select 
    all_events.*
from {{ ref('segment_all_events') }} as all_events
inner join {{ ref('segment_touchpoints') }} as touchpoints
    on all_events.event_id = touchpoints.touchpoint_event_id
order by all_events.occurred_at desc
