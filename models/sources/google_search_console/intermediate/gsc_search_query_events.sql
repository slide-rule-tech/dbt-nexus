{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_search_console', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_search_console', 'intermediate', 'events']
) }}

-- Partial coverage — keyword + page dimensions for analysis.
WITH normalized AS (
    SELECT * FROM {{ ref('gsc_keyword_page') }}
)

SELECT
    {{ nexus.create_nexus_id('event', ['metric_date', 'page', 'query', 'country', 'device', 'site_url']) }} AS event_id,
    CAST(metric_date AS TIMESTAMP) AS occurred_at,
    'metric' AS event_type,
    'search query impressions' AS event_name,
    CONCAT(
        'GSC: "',
        COALESCE(query, ''),
        '" on ',
        COALESCE(page, ''),
        ' - ',
        CAST(impressions AS STRING),
        ' imp, ',
        CAST(clicks AS STRING),
        ' clicks'
    ) AS event_description,
    CAST(1 AS FLOAT64) AS significance,
    'google_search_console' AS source,
    'gsc_keyword_page_report' AS source_table,
    CAST(impressions AS FLOAT64) AS value,
    'impressions' AS value_unit,
    _ingested_at,
    clicks,
    impressions,
    ctr,
    position,
    CAST(NULL AS INT64) AS page_clicks,
    CAST(NULL AS INT64) AS page_impressions,
    CAST(NULL AS FLOAT64) AS page_ctr,
    CAST(NULL AS FLOAT64) AS page_position,
    page,
    query,
    country,
    device,
    CAST(NULL AS STRING) AS search_type,
    site_url AS site
FROM normalized
ORDER BY occurred_at DESC
