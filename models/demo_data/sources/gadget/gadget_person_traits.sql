{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'groups', 'realtime']) }}

WITH shops_traits AS (
    {{ nexus.unpivot_traits(
        model_name='gadget_shops_base',
        columns=['shop_owner_email', 'shop_owner_name'],
        identifier_column='shop_owner_email',
        identifier_type='email',
        additional_columns=["'gadget' as source", "occurred_at"],
        column_to_trait_name={
            'shop_owner_email': 'email',
            'shop_owner_name': 'name'
        }
    ) }}
),



unioned AS (
    SELECT * FROM shops_traits
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