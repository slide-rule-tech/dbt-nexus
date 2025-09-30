-- Nexus Segment Person Identifiers - Touchpoint Filtered
-- Filters segment_all_person_identifiers to only include identifiers from events that exist as touchpoints
-- Joins with segment_touchpoints to ensure only attribution-relevant person identifiers are included

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'persons', 'touchpoints'], 
    materialized='table'
) }}

select 
    all_identifiers.*
from {{ ref('segment_all_person_identifiers') }} as all_identifiers
inner join {{ ref('segment_touchpoints') }} as touchpoints
    on all_identifiers.event_id = touchpoints.touchpoint_event_id
order by all_identifiers.occurred_at desc
