{{ config(
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

WITH shop_events AS (
    SELECT
        event_id,
        occurred_at,
        event_name,
        CONCAT(shop_name, ' ', event_name) as event_description,
        cast(NULL as numeric) as event_value,
        cast(NULL as string) as value_unit,
        'shop_event' as event_type,
        'gadget' as source,
        'shops' as source_table,
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
    FROM {{ ref('gadget_shops_base') }}
)


SELECT * FROM shop_events