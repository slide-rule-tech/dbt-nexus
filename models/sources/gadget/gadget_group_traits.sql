{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'groups', 'realtime']) }}


WITH source_data AS (
    SELECT *
    FROM {{ ref('gadget_shops_base') }}
),

unioned AS (
    SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        'myshopify_domain' AS trait_name,
        myshopify_domain AS trait_value,
        occurred_at,
        source
    FROM source_data

    UNION ALL

    SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        'shop_name' AS trait_name,
        shop_name AS trait_value,
        occurred_at,
        source
    FROM source_data

    UNION ALL

    SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        'name' AS trait_name,
        shop_name AS trait_value,
        occurred_at,
        source
    FROM source_data

    UNION ALL

    SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        'domain' AS trait_name,
        shop_domain AS trait_value,
        occurred_at,
        source
    FROM source_data

    UNION ALL

    SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        'migrated_from_grow' AS trait_name,
        CAST(migrated_from_grow AS STRING) as trait_value,
        occurred_at,
        source
    FROM source_data

    UNION ALL

     SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        'shopify_plan_name' AS trait_name,
        plan_name as trait_value,
        occurred_at,
        source
    FROM source_data

    UNION ALL

    SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        'type' AS trait_name,
        'shopify store' as trait_value,
        occurred_at,
        source
    FROM source_data    

    UNION ALL

    SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        'timezone' AS trait_name,
        timezone as trait_value,
        occurred_at,
        source
    FROM source_data

    UNION ALL

    SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        'shop_owner_email' AS trait_name,
        shop_owner_email as trait_value,
        occurred_at,
        source
    FROM source_data
)

SELECT 
    event_id,
    {{ dbt_utils.generate_surrogate_key(['event_id']) }} as row_id,
    identifier_type,
    identifier_value,
    trait_name,
    trait_value,
    occurred_at,
    source
FROM unioned
order by event_id desc