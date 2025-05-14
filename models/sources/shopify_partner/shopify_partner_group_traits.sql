{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'groups', 'realtime']) }}

WITH source_data AS (
    SELECT *
    FROM {{ ref('shopify_partner_app_events_base') }}
),

unioned AS (
    SELECT
        event_id,
        occurred_at,
        'shop_id' as identifier_type,
        shop_id as identifier_value,
        'myshopify_domain' AS trait_name,
        myshopify_domain AS trait_value
    FROM source_data

    UNION ALL

    SELECT
        event_id,
        occurred_at,
        'shop_id' as identifier_type,
        shop_id as identifier_value,
        'shop_id' AS trait_name,
        shop_id AS trait_value
    FROM source_data
)

SELECT 
    *
FROM unioned
order by event_id desc