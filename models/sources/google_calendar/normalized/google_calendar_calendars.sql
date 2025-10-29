{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['google_calendar', 'normalized']
) }}

-- Normalized layer: Clean, deduplicated calendars with explicit columns
-- Extracts data from STANDARD_TABLE_SCHEMA with _raw_record
WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') as calendar_id,
        _ingested_at,
        _connection_id,
        _stream_id,
        _sync_timestamp,
        _sync_token,
        _raw_record
    FROM {{ ref('google_calendar_calendars_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
),

extracted AS (
    SELECT
        -- Calendar identifier
        calendar_id,
        
        -- Calendar details
        JSON_EXTRACT_SCALAR(_raw_record, '$.summary') as summary,
        JSON_EXTRACT_SCALAR(_raw_record, '$.description') as description,
        JSON_EXTRACT_SCALAR(_raw_record, '$.timeZone') as time_zone,
        JSON_EXTRACT_SCALAR(_raw_record, '$.accessRole') as access_role,
        JSON_EXTRACT_SCALAR(_raw_record, '$.colorId') as color_id,
        JSON_EXTRACT_SCALAR(_raw_record, '$.backgroundColor') as background_color,
        JSON_EXTRACT_SCALAR(_raw_record, '$.foregroundColor') as foreground_color,
        CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.primary') AS BOOL) as is_primary,
        CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.selected') AS BOOL) as is_selected,
        
        -- Sync metadata
        _ingested_at,
        _raw_record as raw_record,
        _connection_id,
        _stream_id,
        _sync_timestamp,
        _sync_token,
        'google_calendar' as source
    FROM source_data
)

SELECT 
    calendar_id,
    summary,
    description,
    time_zone,
    access_role,
    color_id,
    background_color,
    foreground_color,
    is_primary,
    is_selected,
    _ingested_at,
    raw_record,
    _connection_id,
    _stream_id,
    _sync_timestamp,
    _sync_token,
    source
FROM extracted
-- Deduplication: keep latest calendar per calendar_id
QUALIFY row_number() OVER (PARTITION BY calendar_id ORDER BY _ingested_at DESC) = 1
ORDER BY calendar_id

