{{ config(
    materialized='table',
    tags=['dimensions']
) }}

-- Nexus Event Dimensions (Core)
-- Pivots nexus_event_dimensions_unioned into a wide table with one column per dimension.
-- One row per event. Dimension columns are discovered dynamically at compile time.
-- Convention: is_ prefix → BOOLEAN (default FALSE), all others → STRING (default NULL).

-- depends_on: {{ ref('nexus_event_dimensions_unioned') }}

{# Discover distinct dimension_name values at compile time #}
{% set dimension_names = [] %}
{% if execute %}
    {% set names_query %}
        select distinct dimension_name
        from {{ ref('nexus_event_dimensions_unioned') }}
        where dimension_name is not null
        order by dimension_name
    {% endset %}
    {% set dimension_names = run_query(names_query).columns[0].values() %}
{% endif %}

{% if dimension_names | length > 0 %}

WITH dimensions_data AS (
    SELECT * FROM {{ ref('nexus_event_dimensions_unioned') }}
)

SELECT
    event_id,
    occurred_at,
    source,
    {% for name in dimension_names %}
    {% if name.startswith('is_') %}
    COALESCE(MAX(CASE WHEN dimension_name = '{{ name }}' THEN CAST(dimension_value AS BOOLEAN) END), FALSE) as {{ name }}{{ "," if not loop.last }}
    {% else %}
    MAX(CASE WHEN dimension_name = '{{ name }}' THEN dimension_value END) as {{ name }}{{ "," if not loop.last }}
    {% endif %}
    {% endfor %}
FROM dimensions_data
GROUP BY event_id, occurred_at, source

{% else %}

SELECT
    CAST(NULL AS STRING) as event_id,
    CAST(NULL AS TIMESTAMP) as occurred_at,
    CAST(NULL AS STRING) as source
FROM (SELECT 1)
WHERE 1 = 0

{% endif %}
