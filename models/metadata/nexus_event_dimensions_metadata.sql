{{ config(materialized='table') }}

-- Nexus Event Dimensions Metadata
-- Warehouse stats per (dimension_name, source) plus YAML-authored catalog fields.
-- FULL OUTER JOIN surfaces YAML-only dimensions with is_in_data = false.

{% set all_dimensions = var('nexus', {}).get('dimensions', []) %}

{% if all_dimensions | length > 0 %}
WITH yaml_dimensions AS (
    {% set ns = namespace(first=true) %}
    {% for dim in all_dimensions %}
        {% if not ns.first %}UNION ALL{% endif %}
        {% set ns.first = false %}
        {% set raw_label = dim.get('label') %}
        {% if raw_label is not none and raw_label | string | trim != '' %}
            {% set dim_label = raw_label | string | trim %}
        {% else %}
            {% set dim_label = dim.name | replace('_', ' ') | title %}
        {% endif %}
        SELECT
            {{ nexus.metrics_metadata_sql_str(dim.name) }} AS dimension_name,
            {{ nexus.metrics_metadata_sql_str(dim_label) }} AS label,
            {{ nexus.metrics_metadata_sql_str(dim.get('description', '') | trim) }} AS description,
            {% if dim.get('aliases') %}{{ nexus.metrics_metadata_sql_str(dim.aliases | join(', ')) }}{% else %}NULL{% endif %} AS aliases,
            {% if dim.get('tags') %}{{ nexus.metrics_metadata_sql_str(dim.tags | join(', ')) }}{% else %}NULL{% endif %} AS tags,
            {% if dim.get('example_questions') %}{{ nexus.metrics_metadata_sql_str(dim.example_questions | join('; ')) }}{% else %}NULL{% endif %} AS example_questions
    {% endfor %}
),
{% else %}
WITH yaml_dimensions AS (
    SELECT
        CAST(NULL AS VARCHAR) AS dimension_name,
        CAST(NULL AS VARCHAR) AS label,
        CAST(NULL AS VARCHAR) AS description,
        CAST(NULL AS VARCHAR) AS aliases,
        CAST(NULL AS VARCHAR) AS tags,
        CAST(NULL AS VARCHAR) AS example_questions
    WHERE 1 = 0
),
{% endif %}

warehouse_stats AS (
    SELECT
        dimension_name,
        source,
        CASE WHEN dimension_name LIKE 'is_%' THEN 'boolean' ELSE 'string' END AS dimension_type,
        MIN(occurred_at) AS first_seen_at,
        MAX(occurred_at) AS last_seen_at,
        COUNT(*) AS occurrence_count,
        COUNT(DISTINCT dimension_value) AS distinct_values
    FROM {{ ref('nexus_event_dimensions_unioned') }}
    WHERE dimension_name IS NOT NULL
    GROUP BY dimension_name, source
),

-- Up to three distinct example values per (dimension_name, source), by frequency then value (stable).
dimension_value_counts AS (
    SELECT
        dimension_name,
        source,
        dimension_value,
        COUNT(*) AS value_occurrences
    FROM {{ ref('nexus_event_dimensions_unioned') }}
    WHERE dimension_name IS NOT NULL
        AND dimension_value IS NOT NULL
        {% if target.type == 'bigquery' %}
        AND TRIM(CAST(dimension_value AS STRING)) != ''
        {% else %}
        AND TRIM(CAST(dimension_value AS VARCHAR)) != ''
        {% endif %}
    GROUP BY dimension_name, source, dimension_value
),

dimension_examples AS (
    SELECT
        dimension_name,
        source,
        MAX(CASE WHEN rn = 1 THEN dimension_value END) AS example_value_1,
        MAX(CASE WHEN rn = 2 THEN dimension_value END) AS example_value_2,
        MAX(CASE WHEN rn = 3 THEN dimension_value END) AS example_value_3
    FROM (
        SELECT
            dimension_name,
            source,
            dimension_value,
            ROW_NUMBER() OVER (
                PARTITION BY dimension_name, source
                ORDER BY value_occurrences DESC, dimension_value ASC
            ) AS rn
        FROM dimension_value_counts
    ) ranked
    WHERE rn <= 3
    GROUP BY dimension_name, source
)

SELECT
    COALESCE(w.dimension_name, y.dimension_name) AS dimension_name,
    w.source,
    COALESCE(
        w.dimension_type,
        CASE
            WHEN y.dimension_name LIKE 'is_%' THEN 'boolean'
            ELSE 'string'
        END
    ) AS dimension_type,
    COALESCE(
        NULLIF(TRIM(y.label), ''),
        INITCAP(REPLACE(COALESCE(w.dimension_name, y.dimension_name), '_', ' '))
    ) AS label,
    y.description,
    y.aliases,
    y.tags,
    y.example_questions,
    e.example_value_1,
    e.example_value_2,
    e.example_value_3,
    w.first_seen_at,
    w.last_seen_at,
    w.occurrence_count,
    w.distinct_values,
    (w.dimension_name IS NOT NULL) AS is_in_data
FROM warehouse_stats w
LEFT JOIN dimension_examples e
    ON e.dimension_name = w.dimension_name
    AND e.source = w.source
FULL OUTER JOIN yaml_dimensions y ON y.dimension_name = w.dimension_name
ORDER BY COALESCE(w.dimension_name, y.dimension_name), w.source
