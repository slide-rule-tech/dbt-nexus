{{ config(
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

SELECT
        event_id,
        occurred_at,
        event_type as event_name,
        CONCAT(shop_name, ' ', event_type) as event_description,
        cast(NULL as numeric) as event_value,
        cast(NULL as string) as value_unit,
        'shop_event' as event_type,
        'gadget' as source,
        'shops' as source_table, -- Track specific source model
        synced_at,
        -- Custom fields
        shop_id,
        shop_domain,
        shop_name,
        shop_owner_name,
        timezone,
        myshopify_domain,
        migrated_from_grow,
        plan_name,
        shop_owner_email
FROM {{ ref('gadget_shops_base') }}