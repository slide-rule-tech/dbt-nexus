{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime', 'intermediate-layer']
) }}

-- Intermediate layer: Transform normalized data into Nexus event-log format
-- This layer formats data according to specific event types ready for Nexus processing

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
    FROM {{ ref('google_calendar_events_normalized') }}
)

SELECT * FROM source_events
ORDER BY occurred_at DESC
