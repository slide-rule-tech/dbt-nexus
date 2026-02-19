{{ config(materialized='table') }}

WITH distinct_states AS (
    SELECT DISTINCT
        entity_type,
        state_name,
        state_value,
        state_category,
        MIN(state_entered_at) as first_seen_at,
        MAX(state_entered_at) as last_seen_at,
        COUNT(*) as occurrence_count
    FROM {{ ref('nexus_states') }}
    WHERE entity_type IS NOT NULL
        AND state_name IS NOT NULL
        AND (state_value IS NOT NULL OR state_numeric_value IS NOT NULL)
    GROUP BY entity_type, state_name, state_value, state_category
),

state_summary AS (
    SELECT
        entity_type,
        state_name,
        COALESCE(state_category, 'dimension') as state_category,
        COUNT(DISTINCT state_value) as distinct_value_count,
        MIN(first_seen_at) as first_seen_at,
        MAX(last_seen_at) as last_seen_at,
        SUM(occurrence_count) as total_occurrences
    FROM distinct_states
    GROUP BY entity_type, state_name, state_category
),

dimension_values AS (
    SELECT
        entity_type,
        state_name,
        {% if target.type == 'snowflake' %}
        ARRAY_AGG(DISTINCT state_value) WITHIN GROUP (ORDER BY state_value) as possible_values
        {% else %}
        NULL as possible_values
        {% endif %}
    FROM distinct_states
    WHERE COALESCE(state_category, 'dimension') = 'dimension'
    GROUP BY entity_type, state_name
),

measurement_stats AS (
    SELECT
        entity_type,
        state_name,
        MIN(state_numeric_value) as min_value,
        MAX(state_numeric_value) as max_value
    FROM {{ ref('nexus_states') }}
    WHERE state_category = 'measurement'
        AND state_numeric_value IS NOT NULL
    GROUP BY entity_type, state_name
)

SELECT
    ss.entity_type,
    ss.state_name,
    ss.state_category,
    ss.distinct_value_count,
    ss.first_seen_at,
    ss.last_seen_at,
    ss.total_occurrences,
    dv.possible_values,
    ms.min_value,
    ms.max_value
FROM state_summary ss
LEFT JOIN dimension_values dv
    ON ss.entity_type = dv.entity_type
    AND ss.state_name = dv.state_name
LEFT JOIN measurement_stats ms
    ON ss.entity_type = ms.entity_type
    AND ss.state_name = ms.state_name
ORDER BY ss.entity_type, ss.state_category, ss.state_name
