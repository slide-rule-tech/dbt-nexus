{{ config(materialized='table') }}

SELECT DISTINCT
    event_name,
    event_type,
    source
FROM {{ ref('nexus_events') }}
WHERE event_name IS NOT NULL
ORDER BY source, event_type, event_name

