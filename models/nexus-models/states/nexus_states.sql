{{ config(materialized = 'table', tags=['states']) }}

{%- set states = var('states', []) -%}
{% set states_to_union = [] %}
{% for state in states %}
    {% do states_to_union.append(ref(state)) %}
{% endfor %}

{% if states_to_union %}
WITH unioned AS (
    {% for state in states %}
        {{ "UNION ALL" if not loop.first }}
        SELECT 
            {{ common_state_fields() }}
        FROM {{ ref(state) }}
    {% endfor %}
)

SELECT
    {{ common_state_fields() }}
FROM unioned 
ORDER BY state_entered_at DESC

{% else %}
-- Return empty result when no states are configured
WITH empty_result AS (
    SELECT
        {{ common_state_fields(return_empty=true) }}
    WHERE 1 = 0
)

SELECT 
    {{ common_state_fields() }}
FROM empty_result
{% endif %}