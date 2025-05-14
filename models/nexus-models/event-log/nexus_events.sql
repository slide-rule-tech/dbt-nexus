{{ config(materialized = 'table')}}

WITH unioned AS (

    {% for source in var('sources') %}
        {% if source.events %}
            {{ "UNION ALL" if not loop.first }}
            SELECT 
                {{ common_event_fields('FALSE') }}
            FROM {{ ref(source.name ~ '_events') }}
        {% endif %}
    {% endfor %}
)

SELECT
    {{ common_event_fields('FALSE') }}
FROM unioned 
ORDER BY occurred_at DESC