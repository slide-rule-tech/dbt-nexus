{{ config(
    materialized='table',
    tags=['event-processing']
) }}

WITH source_events AS (
    SELECT
        nexus_event_id as event_id,
        event_name,
        start_time as occurred_at,
        event_description,
        null as event_value,
        null as value_unit,
        CASE 
            WHEN has_external_attendees THEN 3
            ELSE 2
        END as event_significance,
        'calendar_event' as event_type,
        source,
        'google_calendar_events' as source_table,
        synced_at,
        CAST(NULL AS BOOL) as realtime_processed
    FROM {{ ref('google_calendar_events_base') }}
)

SELECT * FROM source_events
ORDER BY occurred_at DESC