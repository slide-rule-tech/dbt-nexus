{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_search_console', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'events', 'google_search_console']
) }}

{{ dbt_utils.union_relations(
    relations=[
        ref('gsc_search_impression_events'),
        ref('gsc_search_query_events')
    ]
) }}

ORDER BY occurred_at DESC
