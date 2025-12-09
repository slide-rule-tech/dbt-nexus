{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['google_calendar', 'normalized']
) }}

-- Normalized layer: Clean, deduplicated events with explicit columns
-- Extracts data from new STANDARD_TABLE_SCHEMA with _raw_record
-- Uses iCalUID for cross-account deduplication (like Message-ID for Gmail)
WITH source_data AS (
    SELECT
        _raw_record,
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') as calendar_event_id,
        JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') as ical_uid,
        JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email') as organizer_email,
        _ingested_at,
        _connection_id,
        _stream_id,
        _sync_id,
        _account,
        _sync_metadata
    FROM {{ ref('google_calendar_events_base_dedupped') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
      AND JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') IS NOT NULL
),

extracted AS (
    SELECT
        -- Event identifiers
        null as calendar_id,
        calendar_event_id,
        ical_uid,
        
        -- Determine instanceStart for recurring events
        -- Priority: originalStartTime.dateTime > start.dateTime > start.date
        CAST(PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', 
            COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.originalStartTime.dateTime'),
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            )
        ) AS TIMESTAMP) as instance_start,
        
        -- Event details
        JSON_EXTRACT_SCALAR(_raw_record, '$.summary') as summary,
        JSON_EXTRACT_SCALAR(_raw_record, '$.description') as description,
        JSON_EXTRACT_SCALAR(_raw_record, '$.location') as location,
        JSON_EXTRACT_SCALAR(_raw_record, '$.status') as status,
        
        -- Parse start and end times
        CAST(PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', 
            COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            )
        ) AS TIMESTAMP) as start_time,
        
        CAST(PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', 
            COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.end.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.end.date'), 'T23:59:59Z')
            )
        ) AS TIMESTAMP) as end_time,
        
        -- Check if it's all day event
        CASE 
            WHEN JSON_EXTRACT_SCALAR(_raw_record, '$.start.date') IS NOT NULL THEN true
            ELSE false
        END as is_all_day,
        
        -- Check if it's a recurring event
        -- Event is recurring if:
        -- 1. recurringEventId exists (it's an instance of a recurring event), OR
        -- 2. recurrence array exists (it's the master recurring event)
        CASE 
            WHEN JSON_EXTRACT_SCALAR(_raw_record, '$.recurringEventId') IS NOT NULL THEN true
            WHEN JSON_EXTRACT_ARRAY(_raw_record, '$.recurrence') IS NOT NULL AND ARRAY_LENGTH(JSON_EXTRACT_ARRAY(_raw_record, '$.recurrence')) > 0 THEN true
            ELSE false
        END as is_recurring,
        
        -- Determine if meeting has external attendees (for event classification)
        (
            SELECT COUNT(*) > 0
            FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.attendees')) as attendee
            WHERE JSON_EXTRACT_SCALAR(attendee, '$.email') IS NOT NULL
              AND REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(attendee, '$.email'), r'@(.+)') NOT IN (
                  {%- for domain in var('internal_domains', []) -%}
                  '{{ domain }}'
                  {%- if not loop.last -%},{%- endif -%}
                  {%- endfor -%}
              )
        ) OR (
            JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email') IS NOT NULL
            AND REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email'), r'@(.+)') NOT IN (
                {%- for domain in var('internal_domains', []) -%}
                '{{ domain }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            )
        ) as has_external_attendees,
        
        -- Sync metadata
        _ingested_at,
        _raw_record as raw_record,
        _connection_id,
        _stream_id,
        _sync_id,
        _account,
        _sync_metadata,
        'google_calendar' as source
    FROM source_data
),

-- Create composite key for deduplication
-- For recurring events: ical_uid + instance_start
-- For single events: ical_uid (or ical_uid + start_time + end_time for extra safety)
with_composite_key AS (
    SELECT
        *,
        -- Use iCalUID as primary key for single events
        -- Use iCalUID + instanceStart for recurring events
        CASE 
            WHEN is_recurring THEN CONCAT(ical_uid, '|', CAST(instance_start AS STRING))
            ELSE ical_uid
        END as event_key
    FROM extracted
)

SELECT 
    event_key as event_id,
    calendar_id,
    ical_uid,
    calendar_event_id,
    instance_start,
    summary,
    description,
    location,
    status,
    start_time,
    end_time,
    is_all_day,
    is_recurring,
    has_external_attendees,
    _ingested_at,
    raw_record,
    _connection_id,
    _stream_id,
    _sync_id,
    _account,
    _sync_metadata,
    source
FROM with_composite_key
-- Deduplication: keep latest event per event_key (iCalUID for single, iCalUID + instanceStart for recurring)
QUALIFY row_number() OVER (PARTITION BY event_key ORDER BY _ingested_at DESC) = 1
ORDER BY start_time DESC

