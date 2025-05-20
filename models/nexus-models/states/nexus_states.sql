{{ config(materialized = 'table', tags=['states']))}}

WITH unioned AS (

    {% for state in var('states') %}
        {{ "UNION ALL" if not loop.first }}
        SELECT 
            *
        FROM {{ ref(state) }}
    {% endfor %}
)

SELECT
    *
FROM unioned 
ORDER BY state_entered_at DESC