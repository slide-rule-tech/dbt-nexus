{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime', 'union-layer']
) }}

-- Union layer: Combine all person trait types into final Nexus-compatible tables
-- This layer uses dbt_utils.union_relations() to combine intermediate models

{{ dbt_utils.union_relations([
    ref('google_calendar_event_person_traits')
]) }}

ORDER BY occurred_at DESC