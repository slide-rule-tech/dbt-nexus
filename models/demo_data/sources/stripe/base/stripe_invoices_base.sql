{{ config(
    materialized='table',
    tags=['event-processing']
) }}

WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(data, '$.id') as invoice_id,
        *
    FROM {{ ref('stripe_invoices_raw_demo') }}
),

event_filter AS (
    SELECT
        *
    FROM source_data
),

extracted AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['invoice_id', 'type']) }} as event_id,
        CASE 
            WHEN type = 'invoice.created' THEN 'invoice_created'
            WHEN type = 'invoice.payment_succeeded' THEN 'invoice_paid'
            ELSE type
        END as event_name,
        CAST(TIMESTAMP_SECONDS(CAST(JSON_EXTRACT_SCALAR(data, '$.created') AS INT64)) AS TIMESTAMP) as occurred_at,
        
        -- Invoice details
        invoice_id,
        JSON_EXTRACT_SCALAR(data, '$.customer') as customer_id,
        JSON_EXTRACT_SCALAR(data, '$.customer_email') as customer_email,
        JSON_EXTRACT_SCALAR(data, '$.customer_name') as customer_name,
        JSON_EXTRACT_SCALAR(data, '$.status') as invoice_status,
        CAST(JSON_EXTRACT_SCALAR(data, '$.amount_due') AS INT64) as amount_due,
        CAST(JSON_EXTRACT_SCALAR(data, '$.amount_paid') AS INT64) as amount_paid,
        CAST(JSON_EXTRACT_SCALAR(data, '$.amount_remaining') AS INT64) as amount_remaining,
        JSON_EXTRACT_SCALAR(data, '$.currency') as currency,
        JSON_EXTRACT_SCALAR(data, '$.description') as description,
        JSON_EXTRACT_SCALAR(data, '$.number') as invoice_number,
        JSON_EXTRACT_SCALAR(data, '$.subscription') as subscription_id,
        CAST(JSON_EXTRACT_SCALAR(data, '$.total') AS INT64) as total_amount,
        
        -- Payment details (for payment_succeeded events)
        JSON_EXTRACT_SCALAR(data, '$.charge') as charge_id,
        JSON_EXTRACT_SCALAR(data, '$.payment_intent') as payment_intent_id,
        
        -- Customer details
        STRUCT(
            JSON_EXTRACT_SCALAR(data, '$.customer_email') as email,
            JSON_EXTRACT_SCALAR(data, '$.customer_name') as name,
            REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(data, '$.customer_email'), r'@(.+)') as domain,
            REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(data, '$.customer_email'), r'@(.+)') IN (
                'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 
                'aol.com', 'icloud.com', 'me.com', 'live.com', 'msn.com',
                'googlemail.com', 'ymail.com', 'rocketmail.com', 'protonmail.com',
                'mail.com', 'zoho.com'
            ) as generic_domain,
            REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(data, '$.customer_email'), r'@(.+)') IN (
                {%- for domain in var('internal_domains') -%}
                '{{ domain }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            ) as internal,
            JSON_EXTRACT_SCALAR(data, '$.customer_email') IN (
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
        partition_by='invoice_id',
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
        CONCAT('Invoice ', invoice_number, ' - ', description) as event_description
    FROM deduped_events
)

SELECT * FROM final
ORDER BY occurred_at DESC
