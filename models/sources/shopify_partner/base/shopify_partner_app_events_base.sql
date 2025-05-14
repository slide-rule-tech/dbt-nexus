{{ config(
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(record, '$.id') as event_id,
        *
    FROM {{ source('shopify_partner', 'shopify_app_events') }}
),

event_filter as (
    SELECT
        *
    FROM source_data
    {{ real_time_event_filter('event_id') }}
),

extracted AS (
    SELECT
        event_id,
        PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', JSON_EXTRACT_SCALAR(record, '$.occurred_at')) as occurred_at,
        LOWER(JSON_EXTRACT_SCALAR(record, '$.type')) as event_name,
        'app event' as event_type,
        REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(record, '$.app_id'), r'gid://partners/App/(\d+)') as app_id,
        JSON_EXTRACT_SCALAR(record, '$.app_name') as app_name,
        CAST(JSON_EXTRACT_SCALAR(record, '$.charge_amount') as numeric) as charge_amount,
        JSON_EXTRACT_SCALAR(record, '$.charge_billing_on') as charge_billing_on,
        JSON_EXTRACT_SCALAR(record, '$.charge_currency') as charge_currency,
        REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(record, '$.charge_id'), r'gid://partners/RecurringApplicationCharge/(\d+)') as charge_id,
        JSON_EXTRACT_SCALAR(record, '$.charge_name') as charge_name,
        SAFE_CAST(JSON_EXTRACT_SCALAR(record, '$.charge_test') AS BOOL) as charge_test,
        JSON_EXTRACT_SCALAR(record, '$.description') as description,
        JSON_EXTRACT_SCALAR(record, '$.shop_domain') as myshopify_domain,
        CAST(REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(record, '$.shop_id'), r'gid://partners/Shop/(\d+)') AS STRING) as shop_id,
        JSON_EXTRACT_SCALAR(record, '$.shop_name') as shop_name,
        
        -- nango metadata
        connection_id,
        first_seen_at,
        last_modified_at,
        last_action,
        deleted_at,
        cursor,
        synced_at, -- Original source synced_at (from ingestion pipeline)
        -- Keep the original record for reference
        record as raw_record
    FROM event_filter
),

with_latest_events as (
    {{ get_first_or_last_row(
        source='extracted',
        partition_by='event_id',
        order_by='occurred_at',
        column_label='is_latest',
        get='last'
    ) }}
),

deduped_events as (
    select *
    from with_latest_events
    where is_latest
)

SELECT 
    *,
    'shopify_partner' as source
FROM deduped_events
ORDER BY occurred_at DESC