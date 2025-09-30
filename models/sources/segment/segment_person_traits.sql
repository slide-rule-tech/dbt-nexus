-- Nexus Segment Person Traits - Touchpoint Filtered
-- Filters segment_all_person_traits to only include traits from events that exist as touchpoints
-- Joins with segment_touchpoints to ensure only attribution-relevant person traits are included

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'persons', 'touchpoints'], 
    materialized='table'
) }}

select 
    all_traits.*
from {{ ref('segment_all_person_traits') }} as all_traits
inner join {{ ref('segment_touchpoints') }} as touchpoints
    on all_traits.event_id = touchpoints.touchpoint_event_id
order by all_traits.occurred_at desc
