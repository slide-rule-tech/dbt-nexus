{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'groups']) }}

WITH invoice_group_traits AS (
    {{ nexus.unpivot_traits(
        model_name='stripe_invoices_base',
        columns=['customer_id', 'subscription_id', 'invoice_status', 'currency', 'total_amount'],
        identifier_column='customer_id',
        identifier_type='stripe_customer_id',
        additional_columns=["'stripe' as source", "occurred_at"],
        column_to_trait_name={
            'customer_id': 'stripe_customer_id',
            'subscription_id': 'stripe_subscription_id',
            'invoice_status': 'latest_invoice_status',
            'currency': 'currency',
            'total_amount': 'latest_invoice_amount'
        }
    ) }}
),

payment_group_traits AS (
    {{ nexus.unpivot_traits(
        model_name='stripe_payments_base',
        columns=['customer_id', 'payment_status', 'currency', 'amount_received', 'card_brand', 'card_last4'],
        identifier_column='customer_id',
        identifier_type='stripe_customer_id',
        additional_columns=["'stripe' as source", "occurred_at"],
        column_to_trait_name={
            'customer_id': 'stripe_customer_id',
            'payment_status': 'latest_payment_status',
            'currency': 'currency',
            'amount_received': 'latest_payment_amount',
            'card_brand': 'card_brand',
            'card_last4': 'card_last4'
        }
    ) }}
),

unioned AS (
    SELECT * FROM invoice_group_traits
    UNION ALL
    SELECT * FROM payment_group_traits
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
