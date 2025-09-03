
WITH shops_traits AS (
    {{ nexus.unpivot_traits(
        model_name='gadget_shops_base',
        columns=['myshopify_domain', 'shop_name', 'shop_domain', 'redirected_domain', 'migrated_from_grow', 'plan_name', 'timezone', 'shop_owner_email'],
        identifier_column='shop_id',
        identifier_type='shop_id',
        additional_columns=["'gadget' as source", "occurred_at"],
        column_to_trait_name={
            'myshopify_domain': 'myshopify_domain',
            'shop_name': 'name',
            'shop_domain': 'domain',
            'redirected_domain': 'domain',
            'migrated_from_grow': 'migrated_from_grow',
            'plan_name': 'shopify_plan_name',
            'timezone': 'timezone',
            'shop_owner_email': 'shop_owner_email'
        }
    ) }}
),

shops_additional_traits AS (
    SELECT
        event_id,
        'shop_id' AS identifier_type,
        shop_id AS identifier_value,
        'type' AS trait_name,
        CAST('shopify store' AS STRING) as trait_value,
        'gadget' as source,
        occurred_at
    FROM {{ ref('gadget_shops_base') }}
),

unioned AS (
    SELECT * FROM shops_traits
    UNION ALL
    SELECT * FROM shops_additional_traits
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