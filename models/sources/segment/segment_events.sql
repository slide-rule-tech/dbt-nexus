-- Unioned Layer - Nexus-Ready Segment Events
-- Combines all Segment event types into final Nexus-compatible table
-- Follows four-layer architecture pattern

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'events'], 
    materialized='table'
) }}

{{ dbt_utils.union_relations([
    ref('segment_track_events'),
    ref('segment_page_events'),
    ref('segment_identify_events')
]) }}

order by occurred_at desc
