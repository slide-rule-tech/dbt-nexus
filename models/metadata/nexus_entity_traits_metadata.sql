{{ config(materialized='table') }}

{# Get columns from nexus_entities to find trait columns and their types #}
{% set entities_relation = ref('nexus_entities') %}
{% set entities_columns = adapter.get_columns_in_relation(entities_relation) %}

{# Define non-trait columns to exclude #}
{% set excluded_columns = [
    'entity_id',
    'entity_type',
    '_processed_at',
    '_updated_at',
    '_created_at',
    '_last_merged_at',
    'last_interaction_at',
    'first_interaction_at',
    'traits_entity_id'
] %}

{# Build mapping of trait column names to data types #}
{% set column_type_map = {} %}
{% for col in entities_columns %}
    {% set col_name_lower = col.column.lower() %}
    {% if col_name_lower not in excluded_columns %}
        {% do column_type_map.update({col_name_lower: col.dtype}) %}
    {% endif %}
{% endfor %}

{# Get distinct traits from nexus_entity_traits #}
WITH distinct_traits AS (
    SELECT DISTINCT
        entity_type,
        trait_name,
        lower(replace(trait_name, ' ', '_')) as trait_column_name
    FROM {{ ref('nexus_entity_traits') }}
    WHERE entity_type IS NOT NULL
        AND trait_name IS NOT NULL
)

SELECT
    dt.entity_type,
    dt.trait_name,
    {% if column_type_map %}
        CASE
            {% for col_name, dtype in column_type_map.items() %}
            WHEN dt.trait_column_name = '{{ col_name }}' THEN '{{ dtype }}'
            {% endfor %}
            ELSE NULL
        END as column_type
    {% else %}
        NULL as column_type
    {% endif %}
FROM distinct_traits dt
ORDER BY dt.entity_type, dt.trait_name
