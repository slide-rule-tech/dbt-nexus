-- Unioned Layer - Nexus-Ready Segment Person Traits
-- Combines all Segment person trait types into final Nexus-compatible table
-- Follows four-layer architecture pattern

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'persons'], 
    materialized='table'
) }}

{{ dbt_utils.union_relations([
    ref('segment_identify_person_traits'),
    ref('segment_track_person_traits'),
    ref('segment_page_person_traits')
]) }}

order by occurred_at desc
