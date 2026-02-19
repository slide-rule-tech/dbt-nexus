{{ config(materialized='table') }}

{% set entity_config = nexus.get_entity_type_config() %}
{% set non_er_types = nexus.get_non_er_entity_types() %}

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
    'traits_entity_id',
    'source',
    'source_id',
    '_registered_at'
] %}

{# Build mapping of trait column names to data types #}
{% set column_type_map = {} %}
{% for col in entities_columns %}
    {% set col_name_lower = col.column.lower() %}
    {% if col_name_lower not in excluded_columns %}
        {% do column_type_map.update({col_name_lower: col.dtype}) %}
    {% endif %}
{% endfor %}

{# ER entity traits from nexus_entity_traits EAV #}
WITH er_traits AS (
    SELECT DISTINCT
        entity_type,
        trait_name,
        lower(replace(trait_name, ' ', '_')) as trait_column_name
    FROM {{ ref('nexus_entity_traits') }}
    WHERE entity_type IS NOT NULL
        AND trait_name IS NOT NULL
),

{# Non-ER entity traits from registration model column introspection #}
{# Pre-filter columns to avoid trailing UNION ALL from excluded columns #}
{% set non_er_trait_rows = [] %}
{% for entity_type in non_er_types %}
    {% set type_config = entity_config[entity_type] %}
    {% set reg_model = type_config.get('registration_model') %}
    {% if reg_model %}
        {% set reg_cols = adapter.get_columns_in_relation(ref(reg_model)) %}
        {% set reg_exclude = ['entity_id', 'entity_type', 'source', 'source_id', '_registered_at', '_source_created_at', '_source_updated_at'] %}
        {% for col in reg_cols %}
            {% if col.name | lower not in reg_exclude %}
                {% do non_er_trait_rows.append({'entity_type': entity_type, 'col_name': col.name}) %}
            {% endif %}
        {% endfor %}
    {% endif %}
{% endfor %}

non_er_traits AS (
    {% if non_er_trait_rows | length > 0 %}
    {% for row in non_er_trait_rows %}
    SELECT
        '{{ row.entity_type }}' as entity_type,
        '{{ row.col_name }}' as trait_name,
        '{{ row.col_name | lower }}' as trait_column_name
    {{ "UNION ALL" if not loop.last }}
    {% endfor %}
    {% else %}
    SELECT
        cast(null as string) as entity_type,
        cast(null as string) as trait_name,
        cast(null as string) as trait_column_name
    WHERE 1 = 0
    {% endif %}
),

all_traits AS (
    SELECT * FROM er_traits
    UNION ALL
    SELECT * FROM non_er_traits
)

SELECT
    traits.entity_type,
    traits.trait_name,
    {% if column_type_map %}
        CASE
            {% for col_name, dtype in column_type_map.items() %}
            WHEN traits.trait_column_name = '{{ col_name }}' THEN '{{ dtype }}'
            {% endfor %}
            ELSE NULL
        END as column_type
    {% else %}
        NULL as column_type
    {% endif %}
FROM all_traits traits
ORDER BY traits.entity_type, traits.trait_name
