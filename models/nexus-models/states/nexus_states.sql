{{ config(materialized = 'table', tags=['states']) }}

{# Collect state names to union based on configured states #}
{% set states_list = [] %}

{# Support both new and legacy config patterns #}
{% set nexus_config = var('nexus', {}) %}
{% set states_config = nexus_config.get('states', []) %}

{% if states_config %}
    {# New pattern: nexus.states list #}
    {% for state in states_config %}
        {% do states_list.append(state) %}
    {% endfor %}
{% elif var('states', none) %}
    {# Legacy pattern: states list at root level #}
    {% for state in var('states') %}
        {% do states_list.append(state) %}
    {% endfor %}
{% endif %}

{% if states_list %}
WITH unioned AS (
    {% for state in states_list %}
        {{ "UNION ALL" if not loop.first }}
        SELECT 
            {{ nexus.common_state_fields() }}
        FROM {{ ref(state) }}
    {% endfor %}
)

SELECT
    {{ nexus.common_state_fields() }}
FROM unioned 
ORDER BY state_entered_at DESC

{% else %}
-- Return empty result when no states are configured
WITH empty_result AS (
    SELECT
        {{ nexus.common_state_fields(return_empty=true) }}
)

SELECT 
    {{ nexus.common_state_fields() }}
FROM empty_result
where 1 = 0
{% endif %}