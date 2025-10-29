{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['google_calendar', 'normalized']
) }}

-- Normalized layer: Clean, deduplicated events with explicit columns
-- Extracts data from new STANDARD_TABLE_SCHEMA with _raw_record
WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') as calendar_event_id,
        _ingested_at,
        _connection_id,
        _stream_id,
        _sync_timestamp,
        _sync_token,
        _raw_record
    FROM {{ ref('google_calendar_events_base') }}
),

extracted AS (
    SELECT
        -- Event identifiers
        calendar_event_id,
        
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
        _sync_timestamp,
        _sync_token,
        'google_calendar' as source
    FROM source_data
    WHERE calendar_event_id IS NOT NULL
)

SELECT 
    calendar_event_id,
    summary,
    description,
    location,
    status,
    start_time,
    end_time,
    is_all_day,
    has_external_attendees,
    _ingested_at,
    raw_record,
    _connection_id,
    _stream_id,
    _sync_timestamp,
    _sync_token,
    source
FROM extracted
-- Deduplication: keep latest event per calendar_event_id
QUALIFY row_number() OVER (PARTITION BY calendar_event_id ORDER BY start_time DESC) = 1
ORDER BY start_time DESC

