{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'persons', 'realtime']) }}

WITH invoice_traits AS (
    {{ nexus.unpivot_traits(
        model_name='stripe_invoices_base',
        columns=['customer_email', 'customer_name'],
        identifier_column='customer_email',
        identifier_type='email',
        additional_columns=["'stripe' as source", "occurred_at"],
        column_to_trait_name={
            'customer_email': 'email',
            'customer_name': 'name'
        }
    ) }}
),

payment_traits AS (
    {{ nexus.unpivot_traits(
        model_name='stripe_payments_base',
        columns=['billing_email', 'billing_name', 'billing_phone'],
        identifier_column='COALESCE(billing_email, receipt_email)',
        identifier_type='email',
        additional_columns=["'stripe' as source", "occurred_at"],
        column_to_trait_name={
            'billing_email': 'email',
            'billing_name': 'name',
            'billing_phone': 'phone'
        }
    ) }}
),

unioned AS (
    SELECT * FROM invoice_traits
    UNION ALL
    SELECT * FROM payment_traits
)

SELECT 
    event_id,
    {{ dbt_utils.generate_surrogate_key(['event_id', 'trait_name']) }} as row_id,
    identifier_type,
    identifier_value,
    trait_name,
    trait_value,
    occurred_at,
    source
FROM unioned
WHERE trait_value IS NOT NULL
  AND trait_value != ''
  AND identifier_value IS NOT NULL
  AND identifier_value != ''
ORDER BY event_id DESC
