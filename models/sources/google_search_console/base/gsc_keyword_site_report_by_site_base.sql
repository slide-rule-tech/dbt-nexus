{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_search_console', {}).get('enabled', false),
    materialized='view',
    tags=['google_search_console', 'base']
) }}

SELECT *
FROM {{ source('google_search_console', 'gsc_keyword_site_report_by_site') }}
