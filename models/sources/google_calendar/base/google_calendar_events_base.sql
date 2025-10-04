{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['base-layer']
) }}

-- Base layer: Raw Google Calendar events with minimal transformation
-- This layer provides direct access to the source data with zero transformation overhead
SELECT * 
FROM {{ nexus.nexus_source('google_calendar', 'calendar_events') }}
WHERE deleted_at IS NULL  -- Filter out deleted events