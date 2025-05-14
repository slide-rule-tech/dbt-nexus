{{ config(materialized='view', tags=['identity-resolution', 'event-processing', 'groups', 'realtime']) }}

SELECT
    event_id,
    cast(occurred_at as timestamp) as occurred_at,
    domain,
    organization_id,
    test,
    name,
    cast(synced_at as timestamp) as synced_at
FROM {{ source('manual', 'groups') }}
{{ real_time_event_filter() }} 