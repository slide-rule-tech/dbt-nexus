-- Nexus Segment Events - Touchpoint Filtered
-- Filters segment_all_events to only include events that exist as touchpoints
-- Joins with segment_touchpoints to ensure only attribution-relevant events are included

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'events', 'touchpoints'], 
    materialized='table'
) }}

with all_person_identifiers as (
    {{ dbt_utils.union_relations([
        ref('segment_identify_person_identifiers'),
        ref('segment_track_person_identifiers'),
        ref('segment_page_person_identifiers'),
    ]) }}
)

select * from all_person_identifiers
order by occurred_at desc
