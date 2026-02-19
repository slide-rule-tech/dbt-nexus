{{ config(materialized='table') }}

-- Nexus Event Dimensions Metadata
-- Lists all dimension names, their sources, value types, and summary statistics.
-- Enables self-describing catalog: "What dimensions are available?"

WITH dimension_summary AS (
    SELECT
        dimension_name,
        source,
        CASE WHEN dimension_name LIKE 'is_%' THEN 'boolean' ELSE 'string' END as dimension_type,
        MIN(occurred_at) as first_seen_at,
        MAX(occurred_at) as last_seen_at,
        COUNT(*) as occurrence_count,
        COUNT(DISTINCT dimension_value) as distinct_values
    FROM {{ ref('nexus_event_dimensions_unioned') }}
    WHERE dimension_name IS NOT NULL
    GROUP BY dimension_name, source
)

SELECT
    dimension_name,
    source,
    dimension_type,
    first_seen_at,
    last_seen_at,
    occurrence_count,
    distinct_values
FROM dimension_summary
ORDER BY dimension_name, source
