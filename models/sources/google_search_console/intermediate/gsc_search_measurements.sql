{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_search_console', {}).get('enabled', false),
    materialized='table',
    tags=['google_search_console', 'intermediate', 'measurements']
) }}

WITH search_events AS (
    SELECT event_id, occurred_at, source, clicks, impressions
    FROM {{ ref('gsc_search_impression_events') }}

    UNION ALL

    SELECT event_id, occurred_at, source, clicks, impressions
    FROM {{ ref('gsc_search_query_events') }}
),

clicks_measurement AS (
    SELECT
        {{ nexus.create_nexus_id('event_measurement', ['event_id', "'clicks'"]) }} AS event_measurement_id,
        event_id,
        'clicks' AS measurement_name,
        CAST(clicks AS FLOAT64) AS value,
        'clicks' AS value_unit,
        occurred_at,
        source
    FROM search_events
    WHERE clicks IS NOT NULL
),

impressions_measurement AS (
    SELECT
        {{ nexus.create_nexus_id('event_measurement', ['event_id', "'impressions'"]) }} AS event_measurement_id,
        event_id,
        'impressions' AS measurement_name,
        CAST(impressions AS FLOAT64) AS value,
        'impressions' AS value_unit,
        occurred_at,
        source
    FROM search_events
    WHERE impressions IS NOT NULL
)

SELECT * FROM clicks_measurement
UNION ALL
SELECT * FROM impressions_measurement
