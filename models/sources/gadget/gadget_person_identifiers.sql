{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'groups', 'realtime']) }}


WITH source_data AS (
    SELECT *
    FROM {{ ref('gadget_shops_base') }}
    where shop_owner_email is not null
),

unioned AS (
    SELECT
        event_id,
        'email' AS identifier_type,
        shop_owner_email AS identifier_value,
        occurred_at,
        source
    FROM source_data
)

SELECT 
    event_id,
    {{ dbt_utils.generate_surrogate_key(['event_id']) }} as row_id,
    identifier_type,
    identifier_value,
    occurred_at,
    source
FROM unioned
order by event_id desc