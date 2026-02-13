{{ config(
    materialized='table',
    tags=['measurements']
) }}

-- Nexus Event Measurements (Core)
-- Pivots nexus_event_measurements_unioned into a wide table with one column per measurement.
-- One row per event. Measurement columns are discovered dynamically at compile time.
-- No manual edits needed when new measurement types are added.

-- depends_on: {{ ref('nexus_event_measurements_unioned') }}

{# Discover distinct measurement_name values at compile time #}
{% set measurement_names = [] %}
{% if execute %}
    {% set names_query %}
        select distinct measurement_name
        from {{ ref('nexus_event_measurements_unioned') }}
        where measurement_name is not null
        order by measurement_name
    {% endset %}
    {% set measurement_names = run_query(names_query).columns[0].values() %}
{% endif %}

{% if measurement_names | length > 0 %}

WITH measurements_data AS (
    SELECT * FROM {{ ref('nexus_event_measurements_unioned') }}
)

SELECT
    event_id,
    occurred_at,
    source,
    {% for name in measurement_names %}
    MAX(CASE WHEN measurement_name = '{{ name }}' THEN value END) as {{ name }}{{ "," if not loop.last }}
    {% endfor %}
FROM measurements_data
GROUP BY event_id, occurred_at, source

{% else %}

-- No measurements found - return empty result set
SELECT
    CAST(NULL AS STRING) as event_id,
    CAST(NULL AS TIMESTAMP) as occurred_at,
    CAST(NULL AS STRING) as source
FROM (SELECT 1)
WHERE 1 = 0

{% endif %}
