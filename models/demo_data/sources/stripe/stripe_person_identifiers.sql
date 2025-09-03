{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'persons']) }}

WITH invoice_identifiers AS (
    {{ nexus.unpivot_identifiers(
        model_name='stripe_invoices_base',
        columns=['customer_email'],
        additional_columns=["'stripe' as source", "occurred_at"],
        row_id_field="event_id",
        column_to_identifier_type={
            'customer_email': 'email'
        }
    ) }}
),

payment_identifiers AS (
    {{ nexus.unpivot_identifiers(
        model_name='stripe_payments_base',
        columns=['billing_email', 'receipt_email'],
        additional_columns=["'stripe' as source", "occurred_at"],
        row_id_field="event_id",
        column_to_identifier_type={
            'billing_email': 'email',
            'receipt_email': 'email'
        }
    ) }}
),

unioned AS (
    SELECT * FROM invoice_identifiers
    UNION ALL
    SELECT * FROM payment_identifiers
)

SELECT *
FROM unioned
WHERE identifier_value IS NOT NULL
  AND identifier_value != ''
ORDER BY event_id DESC
