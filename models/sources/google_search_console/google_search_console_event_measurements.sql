{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_search_console', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'measurements', 'google_search_console']
) }}

WITH unioned AS (
    {{ dbt_utils.union_relations(
        relations=[
            ref('gsc_search_measurements')
        ]
    ) }}
)

SELECT *
FROM unioned
ORDER BY occurred_at DESC
