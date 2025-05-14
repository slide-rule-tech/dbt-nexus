{{ config(materialized='view', tags=['event-processing', 'realtime']) }}

WITH source_data AS (
    SELECT
        id as event_id,
        *
    FROM {{ source('manual', 'events') }}
)

SELECT
    *
FROM source_data
{{ real_time_event_filter('event_id') }}