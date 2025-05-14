{{ config(materialized='view', tags=['identity-resolution',  'memberships', 'realtime']) }}

SELECT
    *
FROM {{ source('manual', 'memberships') }}
{{ real_time_event_filter() }} 