{{ config(
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

WITH source_data AS (
    SELECT *
    FROM {{ ref('manual_events_base') }}
)

SELECT
    -- Primary Key
    event_id,
    -- Timestamp
    occurred_at,
    -- Event details
    event_name,
    event_description,
    `value` as event_value,
    value_unit as value_unit,
    -- JSON record
    record,
    -- Metadata
    event_type,
    'manual' as source,
    'manual_events_raw' as source_table,
    -- Timestamps for watermarking and lineage
    synced_at
FROM source_data