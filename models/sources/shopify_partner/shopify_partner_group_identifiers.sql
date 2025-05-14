{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'groups', 'realtime']) }}


WITH source_data AS (
    SELECT *
    FROM {{ ref('shopify_partner_app_events_base') }}
),

unioned AS (
    SELECT
        event_id,
        'myshopify_domain' AS identifier_type,
        myshopify_domain AS identifier_value,
        occurred_at,
        source
    FROM source_data

    UNION ALL

    SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        occurred_at,
        source
    FROM source_data
)

SELECT 
    event_id,
    {{ dbt_utils.generate_surrogate_key(['event_id']) }} as row_id,
    identifier_type,
    identifier_value,
    occurred_at,
    source
FROM unioned
order by event_id desc