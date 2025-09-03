{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'groups']) }}

WITH invoice_group_identifiers AS (
    {{ nexus.unpivot_identifiers(
        model_name='stripe_invoices_base',
        columns=['customer_id', 'subscription_id'],
        additional_columns=["'stripe' as source", "occurred_at"],
        row_id_field="event_id",
        column_to_identifier_type={
            'customer_id': 'stripe_customer_id',
            'subscription_id': 'stripe_subscription_id'
        }
    ) }}
),

payment_group_identifiers AS (
    {{ nexus.unpivot_identifiers(
        model_name='stripe_payments_base',
        columns=['customer_id', 'invoice_id'],
        additional_columns=["'stripe' as source", "occurred_at"],
        row_id_field="event_id",
        column_to_identifier_type={
            'customer_id': 'stripe_customer_id',
            'invoice_id': 'stripe_invoice_id'
        }
    ) }}
),

unioned AS (
    SELECT * FROM invoice_group_identifiers
    UNION ALL
    SELECT * FROM payment_group_identifiers
)

SELECT *
FROM unioned
WHERE identifier_value IS NOT NULL
  AND identifier_value != ''
ORDER BY event_id DESC
