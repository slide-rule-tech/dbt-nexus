{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_search_console', {}).get('enabled', false),
    materialized='table',
    tags=['google_search_console', 'normalized']
) }}

WITH extracted AS (
    SELECT
        _ingested_at,
        PARSE_DATE('%Y-%m-%d', JSON_EXTRACT_SCALAR(_raw_record, '$.date')) AS metric_date,
        JSON_EXTRACT_SCALAR(_raw_record, '$.site_url') AS site_url,
        JSON_EXTRACT_SCALAR(_raw_record, '$.page') AS page,
        JSON_EXTRACT_SCALAR(_raw_record, '$.query') AS query,
        JSON_EXTRACT_SCALAR(_raw_record, '$.country') AS country,
        JSON_EXTRACT_SCALAR(_raw_record, '$.device') AS device,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.clicks') AS INT64) AS clicks,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.impressions') AS INT64) AS impressions,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.ctr') AS FLOAT64) AS ctr,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.position') AS FLOAT64) AS position
    FROM {{ ref('gsc_keyword_page_report_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.date') IS NOT NULL
)

SELECT *
FROM extracted
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY metric_date, site_url, page, query, country, device
    ORDER BY _ingested_at DESC
) = 1
