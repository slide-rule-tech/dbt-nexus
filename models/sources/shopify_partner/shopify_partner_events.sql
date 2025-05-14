{{ config(
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

SELECT
    *,
    CONCAT(shop_name, ' ', event_type, ' ', app_name) as event_description,
    'shopify_app_events' as source_table,
    charge_amount as event_value,
    'USD' as value_unit
FROM {{ ref('shopify_partner_app_events_base') }}