{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['google_calendar', 'normalized']
) }}

-- Normalized participants: Extract, parse, and normalize all participants (organizer, creator, attendees) from Google Calendar events
-- Creates one row per participant per event, with role indicating "organizer", "creator", or "attendee"
WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') as calendar_event_id,
        -- Parse start_time for event timing
        CAST(PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', 
            COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            )
        ) AS TIMESTAMP) as start_time,
        _ingested_at,
        _raw_record
    FROM {{ ref('google_calendar_events_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
),

-- Extract and normalize organizer
organizer_raw AS (
    SELECT
        calendar_event_id,
        start_time,
        _ingested_at,
        JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email') as participant_raw,
        {{ nexus.parse_gmail_email('JSON_EXTRACT_SCALAR(_raw_record, "$.organizer.email")') }} as parsed_email,
        COALESCE(
            JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.displayName'),
            {{ nexus.extract_gmail_name('JSON_EXTRACT_SCALAR(_raw_record, "$.organizer.email")') }}
        ) as participant_name,
        'organizer' as role,
        JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.displayName') as display_name,
        CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.self') AS BOOL) as is_self
    FROM source_data
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email') IS NOT NULL
      AND JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email') != ''
),

organizer_normalized AS (
    SELECT
        calendar_event_id,
        start_time,
        _ingested_at,
        participant_raw,
        participant_name,
        parsed_email,
        {{ nexus.validate_and_normalize_email('parsed_email') }} as normalized_email,
        role,
        display_name,
        is_self,
        NULL as response_status,
        NULL as is_optional,
        NULL as is_organizer
    FROM organizer_raw
    WHERE {{ nexus.validate_and_normalize_email('parsed_email') }} IS NOT NULL
),

-- Extract and normalize creator
creator_raw AS (
    SELECT
        calendar_event_id,
        start_time,
        _ingested_at,
        JSON_EXTRACT_SCALAR(_raw_record, '$.creator.email') as participant_raw,
        {{ nexus.parse_gmail_email('JSON_EXTRACT_SCALAR(_raw_record, "$.creator.email")') }} as parsed_email,
        COALESCE(
            JSON_EXTRACT_SCALAR(_raw_record, '$.creator.displayName'),
            {{ nexus.extract_gmail_name('JSON_EXTRACT_SCALAR(_raw_record, "$.creator.email")') }}
        ) as participant_name,
        'creator' as role,
        JSON_EXTRACT_SCALAR(_raw_record, '$.creator.displayName') as display_name,
        NULL as is_self,
        NULL as response_status,
        NULL as is_optional,
        NULL as is_organizer
    FROM source_data
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.creator.email') IS NOT NULL
      AND JSON_EXTRACT_SCALAR(_raw_record, '$.creator.email') != ''
),

creator_normalized AS (
    SELECT
        calendar_event_id,
        start_time,
        _ingested_at,
        participant_raw,
        participant_name,
        parsed_email,
        {{ nexus.validate_and_normalize_email('parsed_email') }} as normalized_email,
        role,
        display_name,
        is_self,
        response_status,
        is_optional,
        is_organizer
    FROM creator_raw
    WHERE {{ nexus.validate_and_normalize_email('parsed_email') }} IS NOT NULL
),

-- Extract and normalize attendees
attendees_raw AS (
    SELECT
        s.calendar_event_id,
        s.start_time,
        s._ingested_at,
        JSON_EXTRACT_SCALAR(attendee, '$.email') as participant_raw,
        {{ nexus.parse_gmail_email('JSON_EXTRACT_SCALAR(attendee, "$.email")') }} as parsed_email,
        COALESCE(
            JSON_EXTRACT_SCALAR(attendee, '$.displayName'),
            {{ nexus.extract_gmail_name('JSON_EXTRACT_SCALAR(attendee, "$.email")') }}
        ) as participant_name,
        'attendee' as role,
        JSON_EXTRACT_SCALAR(attendee, '$.displayName') as display_name,
        CAST(JSON_EXTRACT_SCALAR(attendee, '$.self') AS BOOL) as is_self,
        JSON_EXTRACT_SCALAR(attendee, '$.responseStatus') as response_status,
        CAST(JSON_EXTRACT_SCALAR(attendee, '$.optional') AS BOOL) as is_optional,
        CAST(JSON_EXTRACT_SCALAR(attendee, '$.organizer') AS BOOL) as is_organizer
    FROM source_data s,
    UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.attendees')) as attendee
    WHERE JSON_EXTRACT_SCALAR(attendee, '$.email') IS NOT NULL
      AND JSON_EXTRACT_SCALAR(attendee, '$.email') != ''
),

attendees_normalized AS (
    SELECT
        calendar_event_id,
        start_time,
        _ingested_at,
        participant_raw,
        participant_name,
        parsed_email,
        {{ nexus.validate_and_normalize_email('parsed_email') }} as normalized_email,
        role,
        display_name,
        is_self,
        response_status,
        is_optional,
        is_organizer
    FROM attendees_raw
    WHERE {{ nexus.validate_and_normalize_email('parsed_email') }} IS NOT NULL
),

-- Union all participants
participants_combined AS (
    SELECT * FROM organizer_normalized
    UNION ALL
    SELECT * FROM creator_normalized
    UNION ALL
    SELECT * FROM attendees_normalized
)

SELECT 
    calendar_event_id,
    participant_raw,
    TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(participant_name, r'^[\'"]+', ''),
            r'[\'"]+$', 
            ''
        )
    ) as name,
    normalized_email as email,
    SPLIT(normalized_email, '@')[SAFE_OFFSET(1)] as domain,
    role,
    start_time,
    _ingested_at
FROM participants_combined
ORDER BY calendar_event_id, 
    CASE role 
        WHEN 'organizer' THEN 1
        WHEN 'creator' THEN 2
        WHEN 'attendee' THEN 3
    END,
    normalized_email

