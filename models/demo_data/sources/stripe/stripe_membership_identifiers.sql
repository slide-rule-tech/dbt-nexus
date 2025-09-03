
-- Stripe memberships connect customers (groups) to their email addresses (persons)
WITH invoice_memberships AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['event_id', "'customer_email'", "'customer_id'"]) }} as membership_id,
        event_id,
        'email' as person_identifier_type,
        customer_email as person_identifier_value,
        'stripe_customer_id' as group_identifier_type,
        customer_id as group_identifier_value,
        occurred_at,
        'stripe' as source
    FROM {{ ref('stripe_invoices_base') }}
    WHERE customer_email IS NOT NULL
      AND customer_email != ''
      AND customer_id IS NOT NULL
      AND customer_id != ''
),

payment_memberships AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['event_id', "'billing_email'", "'customer_id'"]) }} as membership_id,
        event_id,
        'email' as person_identifier_type,
        COALESCE(billing_email, receipt_email) as person_identifier_value,
        'stripe_customer_id' as group_identifier_type,
        customer_id as group_identifier_value,
        occurred_at,
        'stripe' as source
    FROM {{ ref('stripe_payments_base') }}
    WHERE COALESCE(billing_email, receipt_email) IS NOT NULL
      AND COALESCE(billing_email, receipt_email) != ''
      AND customer_id IS NOT NULL
      AND customer_id != ''
),

unioned AS (
    SELECT * FROM invoice_memberships
    UNION ALL
    SELECT * FROM payment_memberships
)

SELECT DISTINCT *
FROM unioned
ORDER BY event_id DESC
