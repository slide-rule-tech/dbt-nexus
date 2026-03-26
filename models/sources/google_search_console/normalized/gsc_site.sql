{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_search_console', {}).get('enabled', false),
    materialized='table',
    tags=['google_search_console', 'normalized']
) }}

-- Join site-level (deduped impressions) with page-level impression counting on shared dimensions.
-- Nango payload: metrics live in _raw_record JSON.

WITH by_site AS (
    SELECT
        _ingested_at,
        PARSE_DATE('%Y-%m-%d', JSON_EXTRACT_SCALAR(_raw_record, '$.date')) AS metric_date,
        JSON_EXTRACT_SCALAR(_raw_record, '$.site_url') AS site_url,
        JSON_EXTRACT_SCALAR(_raw_record, '$.country') AS country,
        JSON_EXTRACT_SCALAR(_raw_record, '$.device') AS device,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.clicks') AS INT64) AS clicks,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.impressions') AS INT64) AS impressions,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.ctr') AS FLOAT64) AS ctr,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.position') AS FLOAT64) AS position
    FROM {{ ref('gsc_site_report_by_site_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.date') IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY
            PARSE_DATE('%Y-%m-%d', JSON_EXTRACT_SCALAR(_raw_record, '$.date')),
            JSON_EXTRACT_SCALAR(_raw_record, '$.site_url'),
            JSON_EXTRACT_SCALAR(_raw_record, '$.country'),
            JSON_EXTRACT_SCALAR(_raw_record, '$.device')
        ORDER BY _ingested_at DESC
    ) = 1
),

by_page AS (
    SELECT
        _ingested_at,
        PARSE_DATE('%Y-%m-%d', JSON_EXTRACT_SCALAR(_raw_record, '$.date')) AS metric_date,
        JSON_EXTRACT_SCALAR(_raw_record, '$.site_url') AS site_url,
        JSON_EXTRACT_SCALAR(_raw_record, '$.country') AS country,
        JSON_EXTRACT_SCALAR(_raw_record, '$.device') AS device,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.clicks') AS INT64) AS page_clicks,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.impressions') AS INT64) AS page_impressions,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.ctr') AS FLOAT64) AS page_ctr,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.position') AS FLOAT64) AS page_position
    FROM {{ ref('gsc_site_report_by_page_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.date') IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY
            PARSE_DATE('%Y-%m-%d', JSON_EXTRACT_SCALAR(_raw_record, '$.date')),
            JSON_EXTRACT_SCALAR(_raw_record, '$.site_url'),
            JSON_EXTRACT_SCALAR(_raw_record, '$.country'),
            JSON_EXTRACT_SCALAR(_raw_record, '$.device')
        ORDER BY _ingested_at DESC
    ) = 1
)

SELECT
    s.metric_date,
    s.site_url,
    s.country,
    s.device,
    s.clicks,
    s.impressions,
    s.ctr,
    s.position,
    p.page_clicks,
    p.page_impressions,
    p.page_ctr,
    p.page_position,
    s._ingested_at
FROM by_site AS s
LEFT JOIN by_page AS p
    ON s.metric_date = p.metric_date
    AND s.site_url = p.site_url
    AND s.country = p.country
    AND s.device = p.device
