-- Unioned Layer - Nexus-Ready Segment Person Identifiers
-- Combines all Segment person identifier types into final Nexus-compatible table
-- Follows four-layer architecture pattern

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'persons'], 
    materialized='table'
) }}

{{ dbt_utils.union_relations([
    ref('segment_track_person_identifiers'),
    ref('segment_page_person_identifiers'),
    ref('segment_identify_person_identifiers')
]) }}

order by occurred_at desc

