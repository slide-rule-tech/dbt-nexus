{{ config(materialized='table') }}

-- Nexus Event Measurements Metadata
-- Lists all measurement names, their units, sources, and summary statistics.
-- Enables self-describing catalog: "What measurements are available?"

WITH measurement_summary AS (
    SELECT
        measurement_name,
        value_unit,
        source,
        MIN(occurred_at) as first_seen_at,
        MAX(occurred_at) as last_seen_at,
        COUNT(*) as occurrence_count,
        AVG(value) as avg_value,
        MIN(value) as min_value,
        MAX(value) as max_value
    FROM {{ ref('nexus_event_measurements') }}
    WHERE measurement_name IS NOT NULL
    GROUP BY measurement_name, value_unit, source
)

SELECT
    measurement_name,
    value_unit,
    source,
    first_seen_at,
    last_seen_at,
    occurrence_count,
    avg_value,
    min_value,
    max_value
FROM measurement_summary
ORDER BY measurement_name, source
