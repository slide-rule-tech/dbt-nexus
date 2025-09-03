{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'groups', 'realtime']) }}

WITH shops_identifiers AS (
    {{ nexus.unpivot_identifiers(
        model_name='gadget_shops_base',
        columns=['myshopify_domain', 'shop_id', 'shop_domain', 'redirected_domain'],
        additional_columns=["'gadget' as source", "occurred_at"],
        row_id_field="event_id",
        column_to_identifier_type={
            'myshopify_domain': 'myshopify_domain',
            'shop_id': 'shop_id',
            'shop_domain': 'domain',
            'redirected_domain': 'domain'
        }
    ) }}
),


unioned AS (
    SELECT * FROM shops_identifiers
)

SELECT *
FROM unioned
order by occurred_at desc