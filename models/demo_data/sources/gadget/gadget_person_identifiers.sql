
WITH shops_identifiers AS (
    {{ nexus.unpivot_identifiers(
        model_name='gadget_shops_base',
        columns=['shop_owner_email'],
        additional_columns=["'gadget' as source", "occurred_at"],
        row_id_field="event_id",
        column_to_identifier_type={
            'shop_owner_email': 'email'
        }
    ) }}
),

unioned AS (
    SELECT * FROM shops_identifiers
)

SELECT *
FROM unioned
order by event_id desc