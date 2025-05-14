{{ config(materialized='view', tags=['realtime']) }}

WITH source_event AS (
    SELECT *
    FROM {{ ref(var('realtime_event_model')) }} -- DIRECTIVE: inject alasql sql table=source_event_model
)

SELECT
    {{ common_event_fields('TRUE') }}
FROM source_event 