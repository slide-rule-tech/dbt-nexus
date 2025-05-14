{{ config(materialized='view', tags=['identity-resolution',  'memberships', 'realtime']) }}

WITH source_data AS (
    SELECT *
    FROM {{ ref('gadget_shops_base') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['event_id', 'shop_owner_email', 'shop_id']) }} as id,
    event_id,
    occurred_at,
    shop_owner_email as person_identifier,
    'email' as person_identifier_type,
    shop_id as group_identifier,
    'shop_id' as group_identifier_type,
    'owner' as role,
    'gadget' as source
FROM source_data
WHERE shop_owner_email IS NOT NULL 