{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='view',
    tags=['google_calendar', 'base']
) }}

-- Base layer: Raw table with zero transformation overhead
SELECT * 
FROM {{ source('google_calendar', 'events') }}