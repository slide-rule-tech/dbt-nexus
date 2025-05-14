{{ config(
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

with source_data as (
    select 
        {{ dbt_utils.generate_surrogate_key(['JSON_EXTRACT_SCALAR(record, "$.id")']) }} as event_id,
        PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', JSON_EXTRACT_SCALAR(record, '$.updatedAt')) as occurred_at,
        JSON_EXTRACT_SCALAR(record, '$.id') as shop_id,
        JSON_EXTRACT_SCALAR(record, '$.domain') as shop_domain,
        JSON_EXTRACT_SCALAR(record, '$.name') as shop_name,
        -- Additional fields requested
         JSON_EXTRACT_SCALAR(record, '$.shopOwner') as shop_owner_name,
        JSON_EXTRACT_SCALAR(record, '$.timezone') as timezone,
        JSON_EXTRACT_SCALAR(record, '$.myshopifyDomain') as myshopify_domain,
        CAST(JSON_EXTRACT_SCALAR(record, '$.migratedFromGrow') AS BOOL) as migrated_from_grow,
        JSON_EXTRACT_SCALAR(record, '$.planName') as plan_name,
        JSON_EXTRACT_SCALAR(record, '$.email') as shop_owner_email,
        'shop_updated' as event_type,
        -- Keep the original record for reference
        record as raw_record,
        synced_at
    from {{ source('gadget', 'shops') }}
),

event_filter as (
    SELECT
        *
    FROM source_data
    {{ real_time_event_filter('event_id') }}
),


with_latest_events as (
    {{ get_first_or_last_row(
        source='event_filter',
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

select 
    *,
    'gadget' as source,
from deduped_events
order by occurred_at desc