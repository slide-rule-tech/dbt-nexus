{{ config(
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(data, '$.id') as payment_intent_id,
        *
    FROM {{ ref('stripe_payments_raw_demo') }}
),

event_filter AS (
    SELECT
        *
    FROM source_data
    {{ real_time_event_filter('payment_intent_id') }}
),

extracted AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['payment_intent_id', 'type']) }} as event_id,
        CASE 
            WHEN type = 'payment_intent.succeeded' THEN 'payment_succeeded'
            ELSE type
        END as event_name,
        CAST(TIMESTAMP_SECONDS(CAST(JSON_EXTRACT_SCALAR(data, '$.created') AS INT64)) AS TIMESTAMP) as occurred_at,
        
        -- Payment intent details
        payment_intent_id,
        JSON_EXTRACT_SCALAR(data, '$.customer') as customer_id,
        JSON_EXTRACT_SCALAR(data, '$.invoice') as invoice_id,
        JSON_EXTRACT_SCALAR(data, '$.status') as payment_status,
        CAST(JSON_EXTRACT_SCALAR(data, '$.amount') AS INT64) as amount,
        CAST(JSON_EXTRACT_SCALAR(data, '$.amount_received') AS INT64) as amount_received,
        JSON_EXTRACT_SCALAR(data, '$.currency') as currency,
        JSON_EXTRACT_SCALAR(data, '$.description') as description,
        JSON_EXTRACT_SCALAR(data, '$.receipt_email') as receipt_email,
        
        -- Charge details from the charges array
        JSON_EXTRACT_SCALAR(data, '$.charges.data[0].id') as charge_id,
        JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.name') as billing_name,
        JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.email') as billing_email,
        JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.phone') as billing_phone,
        JSON_EXTRACT_SCALAR(data, '$.charges.data[0].payment_method_details.card.brand') as card_brand,
        JSON_EXTRACT_SCALAR(data, '$.charges.data[0].payment_method_details.card.last4') as card_last4,
        JSON_EXTRACT_SCALAR(data, '$.charges.data[0].outcome.risk_level') as risk_level,
        CAST(JSON_EXTRACT_SCALAR(data, '$.charges.data[0].outcome.risk_score') AS INT64) as risk_score,
        
        -- Billing address
        STRUCT(
            JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.address.line1') as line1,
            JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.address.line2') as line2,
            JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.address.city') as city,
            JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.address.state') as state,
            JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.address.postal_code') as postal_code,
            JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.address.country') as country
        ) as billing_address,
        
        -- Customer details
        STRUCT(
            COALESCE(
                JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.email'),
                JSON_EXTRACT_SCALAR(data, '$.receipt_email')
            ) as email,
            JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.name') as name,
            REGEXP_EXTRACT(
                COALESCE(
                    JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.email'),
                    JSON_EXTRACT_SCALAR(data, '$.receipt_email')
                ), r'@(.+)'
            ) as domain,
            REGEXP_EXTRACT(
                COALESCE(
                    JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.email'),
                    JSON_EXTRACT_SCALAR(data, '$.receipt_email')
                ), r'@(.+)'
            ) IN (
                'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 
                'aol.com', 'icloud.com', 'me.com', 'live.com', 'msn.com',
                'googlemail.com', 'ymail.com', 'rocketmail.com', 'protonmail.com',
                'mail.com', 'zoho.com'
            ) as generic_domain,
            REGEXP_EXTRACT(
                COALESCE(
                    JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.email'),
                    JSON_EXTRACT_SCALAR(data, '$.receipt_email')
                ), r'@(.+)'
            ) IN (
                {%- for domain in var('internal_domains') -%}
                '{{ domain }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            ) as internal,
            COALESCE(
                JSON_EXTRACT_SCALAR(data, '$.charges.data[0].billing_details.email'),
                JSON_EXTRACT_SCALAR(data, '$.receipt_email')
            ) IN (
                {%- for email in var('test_emails') -%}
                '{{ email }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            ) as test
        ) as customer,
        
        -- Keep the original record for reference
        data as raw_record,
        type as stripe_event_type,
        synced_at
    FROM event_filter
),

with_latest_events AS (
    {{ get_first_or_last_row(
        source='extracted',
        partition_by='payment_intent_id',
        order_by='occurred_at',
        column_label='is_latest',
        get='last'
    ) }}
),

deduped_events AS (
    SELECT *
    FROM with_latest_events
    WHERE is_latest
),

final AS (
    SELECT 
        *,
        'stripe' as source,
        CONCAT('Payment $', ROUND(amount/100, 2), ' - ', description) as event_description
    FROM deduped_events
)

SELECT * FROM final
ORDER BY occurred_at DESC
