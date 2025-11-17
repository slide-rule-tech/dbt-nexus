{{ config(materialized='table') }}

{# Get columns from nexus_attribution_model_results to find attribution field columns #}
{% set attribution_results_relation = ref('nexus_attribution_model_results') %}
{% set attribution_columns = adapter.get_columns_in_relation(attribution_results_relation) %}

{# Define non-attribution columns to exclude (standard fields) #}
{% set excluded_columns = [
    'attribution_model_result_id',
    '_dbt_source_relation',
    'touchpoint_occurred_at',
    'attribution_model_name',
    'touchpoint_batch_id',
    'touchpoint_event_id',
    'attributed_event_id',
    'entity_id',
    'entity_type',
    'attributed_event_occurred_at'
] %}

{# Build list of attribution field columns #}
{% set attribution_field_columns = [] %}
{% for col in attribution_columns %}
    {% set col_name_lower = col.column.lower() %}
    {% if col_name_lower not in excluded_columns %}
        {% do attribution_field_columns.append(col_name_lower) %}
    {% endif %}
{% endfor %}

{# Build UNION ALL query to check for non-null values for each attribution field per model #}
{% if attribution_field_columns %}
    {% set union_queries = [] %}
    {% for field in attribution_field_columns %}
        {% set field_query %}
            SELECT DISTINCT
                attribution_model_name,
                '{{ field }}' as attribution_field
            FROM {{ ref('nexus_attribution_model_results') }}
            WHERE attribution_model_name IS NOT NULL
                AND {{ field }} IS NOT NULL
        {% endset %}
        {% do union_queries.append(field_query) %}
    {% endfor %}
    
    {{ union_queries | join('\n    UNION ALL\n    ') }}
    ORDER BY attribution_model_name, attribution_field
{% else %}
    -- No attribution fields found
    SELECT 
        CAST(NULL AS STRING) AS attribution_model_name,
        CAST(NULL AS STRING) AS attribution_field
    WHERE 1 = 0
{% endif %}

