{{ config(
    materialized='table',
    tags=['event-processing']
) }}

with source_data as (
    select 
        {{ dbt_utils.generate_surrogate_key(['id']) }} as event_id,
        'shop_created' as event_name,
        PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', COALESCE(JSON_EXTRACT_SCALAR(record, '$.shopifyCreatedAt'), JSON_EXTRACT_SCALAR(record, '$.createdAt'))) as occurred_at,
        JSON_EXTRACT_SCALAR(record, '$.id') as shop_id,
        JSON_EXTRACT_SCALAR(record, '$.domain') as shop_domain,
        {{ redirected_domain("JSON_EXTRACT_SCALAR(record, '$.domain')") }} as redirected_domain,
        JSON_EXTRACT_SCALAR(record, '$.name') as shop_name,
        -- Additional fields requested
         JSON_EXTRACT_SCALAR(record, '$.shopOwner') as shop_owner_name,
        JSON_EXTRACT_SCALAR(record, '$.timezone') as timezone,
        JSON_EXTRACT_SCALAR(record, '$.myshopifyDomain') as myshopify_domain,
        CAST(JSON_EXTRACT_SCALAR(record, '$.migratedFromGrow') AS BOOL) as migrated_from_grow,
        JSON_EXTRACT_SCALAR(record, '$.planName') as plan_name,
        JSON_EXTRACT_SCALAR(record, '$.email') as shop_owner_email,
        
        -- Keep the original record for reference
        record as raw_record,
        synced_at
    from {{ ref('shopify_shops_raw_demo') }}
),

with_latest_events as (
    {{ get_first_or_last_row(
        source='source_data',
        partition_by='shop_id',
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

select 
    *,
    'gadget' as source,
from deduped_events
order by occurred_at desc