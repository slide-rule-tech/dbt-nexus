{{ config(materialized='view', tags=['identity-resolution', 'event-processing', 'persons', 'realtime']) }}

SELECT
    event_id,
    cast(occurred_at as timestamp) as occurred_at,
    email,
    name,
    cast(synced_at as timestamp) as synced_at,
    phone,
    user_id
FROM {{ source('manual', 'persons') }}
{{ real_time_event_filter() }}