{{ config(
    materialized='table',
    tags=['event-processing']
) }}

WITH invoice_events AS (
    SELECT
        event_id,
        occurred_at,
        event_name,
        event_description,
        CASE 
            WHEN event_name = 'invoice_paid' THEN amount_paid
            ELSE amount_due
        END as event_value,
        currency as value_unit,
        'invoice_event' as event_type,
        'stripe' as source,
        'invoices' as source_table,
        synced_at,
        cast(NULL as string) as oauth_connection_id,
        cast(NULL as string) as connection_email,
        cast(NULL as bool) as needs_reconnect,
        -- Event parameters
        cast(NULL as string) as ga_account_name,
        cast(NULL as string) as ga_property_name,
        cast(NULL as string) as ga_data_stream_name,
        cast(NULL as string) as ga_data_stream_path,
        cast(NULL as string) as ga_measurement_id,
        cast(NULL as bool) as use_slide_rule_tracker,
        cast(NULL as bool) as used_for_reporting,
        cast(NULL as bool) as used_for_tracking
    FROM {{ ref('stripe_invoices_base') }}
),

payment_events AS (
    SELECT
        event_id,
        occurred_at,
        event_name,
        event_description,
        amount_received as event_value,
        currency as value_unit,
        'payment_event' as event_type,
        'stripe' as source,
        'payments' as source_table,
        synced_at,
        cast(NULL as string) as oauth_connection_id,
        cast(NULL as string) as connection_email,
        cast(NULL as bool) as needs_reconnect,
        -- Event parameters
        cast(NULL as string) as ga_account_name,
        cast(NULL as string) as ga_property_name,
        cast(NULL as string) as ga_data_stream_name,
        cast(NULL as string) as ga_data_stream_path,
        cast(NULL as string) as ga_measurement_id,
        cast(NULL as bool) as use_slide_rule_tracker,
        cast(NULL as bool) as used_for_reporting,
        cast(NULL as bool) as used_for_tracking
    FROM {{ ref('stripe_payments_base') }}
),

unioned AS (
    SELECT * FROM invoice_events
    UNION ALL
    SELECT * FROM payment_events
)

SELECT * FROM unioned
ORDER BY occurred_at DESC
