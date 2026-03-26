{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_search_console', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_search_console', 'intermediate', 'events']
) }}

-- 100% of traffic — site + page impression counting perspectives (no query/page dimensions).
WITH normalized AS (
    SELECT * FROM {{ ref('gsc_site') }}
)

SELECT
    {{ nexus.create_nexus_id('event', ['metric_date', 'country', 'device', 'site_url']) }} AS event_id,
    CAST(metric_date AS TIMESTAMP) AS occurred_at,
    'metric' AS event_type,
    'search impressions' AS event_name,
    CONCAT(
        'GSC: ',
        COALESCE(site_url, ''),
        ' - ',
        CAST(impressions AS STRING),
        ' imp, ',
        CAST(clicks AS STRING),
        ' clicks'
    ) AS event_description,
    CAST(1 AS FLOAT64) AS significance,
    'google_search_console' AS source,
    'gsc_site_report_by_site' AS source_table,
    CAST(impressions AS FLOAT64) AS value,
    'impressions' AS value_unit,
    _ingested_at,
    clicks,
    impressions,
    ctr,
    position,
    page_clicks,
    page_impressions,
    page_ctr,
    page_position,
    CAST(NULL AS STRING) AS page,
    CAST(NULL AS STRING) AS query,
    country,
    device,
    CAST(NULL AS STRING) AS search_type,
    site_url AS site
FROM normalized
ORDER BY occurred_at DESC
