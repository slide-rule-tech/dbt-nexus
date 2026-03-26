{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_search_console', {}).get('enabled', false),
    materialized='table',
    tags=['google_search_console', 'intermediate', 'dimensions']
) }}

WITH search_events AS (
    SELECT
        event_id,
        occurred_at,
        source,
        query,
        page,
        country,
        device,
        search_type,
        site
    FROM {{ ref('gsc_search_impression_events') }}

    UNION ALL

    SELECT
        event_id,
        occurred_at,
        source,
        query,
        page,
        country,
        device,
        search_type,
        site
    FROM {{ ref('gsc_search_query_events') }}
),

query_dimension AS (
    SELECT
        {{ nexus.create_nexus_id('event_dimension', ['event_id', "'query'"]) }} AS event_dimension_id,
        event_id,
        'query' AS dimension_name,
        query AS dimension_value,
        occurred_at,
        source
    FROM search_events
    WHERE query IS NOT NULL
),

page_dimension AS (
    SELECT
        {{ nexus.create_nexus_id('event_dimension', ['event_id', "'page'"]) }} AS event_dimension_id,
        event_id,
        'page' AS dimension_name,
        page AS dimension_value,
        occurred_at,
        source
    FROM search_events
    WHERE page IS NOT NULL
),

country_dimension AS (
    SELECT
        {{ nexus.create_nexus_id('event_dimension', ['event_id', "'country'"]) }} AS event_dimension_id,
        event_id,
        'country' AS dimension_name,
        country AS dimension_value,
        occurred_at,
        source
    FROM search_events
    WHERE country IS NOT NULL
),

device_dimension AS (
    SELECT
        {{ nexus.create_nexus_id('event_dimension', ['event_id', "'device'"]) }} AS event_dimension_id,
        event_id,
        'device' AS dimension_name,
        device AS dimension_value,
        occurred_at,
        source
    FROM search_events
    WHERE device IS NOT NULL
),

search_type_dimension AS (
    SELECT
        {{ nexus.create_nexus_id('event_dimension', ['event_id', "'search_type'"]) }} AS event_dimension_id,
        event_id,
        'search_type' AS dimension_name,
        search_type AS dimension_value,
        occurred_at,
        source
    FROM search_events
    WHERE search_type IS NOT NULL
),

site_dimension AS (
    SELECT
        {{ nexus.create_nexus_id('event_dimension', ['event_id', "'site'"]) }} AS event_dimension_id,
        event_id,
        'site' AS dimension_name,
        site AS dimension_value,
        occurred_at,
        source
    FROM search_events
    WHERE site IS NOT NULL
)

SELECT * FROM query_dimension
UNION ALL
SELECT * FROM page_dimension
UNION ALL
SELECT * FROM country_dimension
UNION ALL
SELECT * FROM device_dimension
UNION ALL
SELECT * FROM search_type_dimension
UNION ALL
SELECT * FROM site_dimension
