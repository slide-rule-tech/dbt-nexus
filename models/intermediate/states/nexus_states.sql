{{ config(materialized = 'table', tags=['states']) }}

{# Collect state names to union based on configured states #}
{% set states_list = [] %}

{# Support both new and legacy config patterns #}
{% set nexus_config = var('nexus', {}) %}
{% set states_config = nexus_config.get('states', []) %}

{% if states_config %}
    {% for state in states_config %}
        {% do states_list.append(state) %}
    {% endfor %}
{% elif var('states', none) %}
    {% for state in var('states') %}
        {% do states_list.append(state) %}
    {% endfor %}
{% endif %}

{% if states_list %}
WITH unioned AS (
    {% for state in states_list %}
        {{ "UNION ALL" if not loop.first }}
        {# Check whether the source state model provides the new columns.
           If not, default to NULL / 'dimension' for backward compatibility. #}
        {% set state_cols = [] %}
        {% if execute %}
            {% set state_relation = ref(state) %}
            {% set introspected = adapter.get_columns_in_relation(state_relation) %}
            {% set state_cols = introspected | map(attribute='name') | map('lower') | list %}
        {% endif %}
        SELECT
            {{ nexus.create_nexus_id('state', ['entity_id', 'state_name', 'state_entered_at', 'trigger_event_id']) }} AS state_id,
            entity_id,
            entity_type,
            state_name,
            state_value,
            {% if 'state_numeric_value' in state_cols %}
            state_numeric_value,
            {% else %}
            CAST(NULL AS NUMERIC) AS state_numeric_value,
            {% endif %}
            {% if 'state_category' in state_cols %}
            state_category,
            {% else %}
            'dimension' AS state_category,
            {% endif %}
            state_entered_at,
            state_exited_at,
            is_current,
            trigger_event_id
        FROM {{ ref(state) }}
    {% endfor %}
)

SELECT
    {{ nexus.common_state_fields() }}
FROM unioned
ORDER BY state_entered_at DESC

{% else %}
WITH empty_result AS (
    SELECT
        {{ nexus.common_state_fields(return_empty=true) }}
)

SELECT
    {{ nexus.common_state_fields() }}
FROM empty_result
where 1 = 0
{% endif %}
