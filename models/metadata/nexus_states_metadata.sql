{{ config(materialized='table') }}

-- Nexus States Metadata
-- Lists all state names, their possible values, and metadata about each state

WITH distinct_states AS (
    SELECT DISTINCT
        entity_type,
        state_name,
        state_value,
        MIN(state_entered_at) as first_seen_at,
        MAX(state_entered_at) as last_seen_at,
        COUNT(*) as occurrence_count
    FROM {{ ref('nexus_states') }}
    WHERE entity_type IS NOT NULL
        AND state_name IS NOT NULL
        AND state_value IS NOT NULL
    GROUP BY entity_type, state_name, state_value
),

state_summary AS (
    SELECT
        entity_type,
        state_name,
        COUNT(DISTINCT state_value) as distinct_value_count,
        MIN(first_seen_at) as first_seen_at,
        MAX(last_seen_at) as last_seen_at,
        SUM(occurrence_count) as total_occurrences
    FROM distinct_states
    GROUP BY entity_type, state_name
),

state_values_aggregated AS (
    SELECT
        entity_type,
        state_name,
        {% if target.type == 'snowflake' %}
        ARRAY_AGG(DISTINCT state_value) WITHIN GROUP (ORDER BY state_value) as possible_values
        {% else %}
        NULL as possible_values
        {% endif %}
    FROM distinct_states
    GROUP BY entity_type, state_name
)

SELECT
    ss.entity_type,
    ss.state_name,
    ss.distinct_value_count,
    ss.first_seen_at,
    ss.last_seen_at,
    ss.total_occurrences,
    sva.possible_values
FROM state_summary ss
LEFT JOIN state_values_aggregated sva
    ON ss.entity_type = sva.entity_type
    AND ss.state_name = sva.state_name
ORDER BY ss.entity_type, ss.state_name