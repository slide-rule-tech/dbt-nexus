{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['event_id']),
    unique_key=['event_id', 'email', 'role'],
    on_schema_change='append_new_columns',
    tags=['google_calendar', 'normalized']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'event_id']) }}

-- Normalized participants: Extract, parse, and normalize all participants (organizer, creator, attendees) from Google Calendar events
-- Creates one row per participant per event, with role indicating "organizer", "creator", or "attendee"
-- Uses iCalUID + instanceStart for cross-account deduplication (like Message-ID
-- for Gmail), normalized against recurring-series re-cuts. The key itself is
-- computed once in the base dedup view and selected here -- it MUST match the
-- one google_calendar_events_normalized carries, because the downstream
-- intermediates join participants to events by re-hashing this value, and
-- nothing tests that join.
WITH source_data AS (
    SELECT
        event_key as event_id,
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') as calendar_event_id,
        JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') as ical_uid,
        {{ nexus.google_calendar_instance_start('_raw_record') }} as instance_start,
        -- Parse start_time for event timing
        {% if target.type == 'bigquery' %}SAFE_CAST(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            ) AS TIMESTAMP){% else %}try_cast(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            ) AS TIMESTAMP){% endif %} as start_time,
        _ingested_at,
        _raw_record
    FROM {{ ref('google_calendar_events_base_dedupped') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
    {% if is_incremental() %}
      AND _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
    {% endif %}
      AND JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') IS NOT NULL
),

-- Extract and normalize organizer
organizer_raw AS (
    SELECT
        event_id,
        ical_uid,
        calendar_event_id,
        instance_start,
        start_time,
        _ingested_at,
        JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email') as participant_raw,
        {{ nexus.parse_gmail_email("JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email')") }} as parsed_email,
        COALESCE(
            JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.displayName'),
            {{ nexus.extract_gmail_name("JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email')") }}
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
        event_id,
        ical_uid,
        calendar_event_id,
        instance_start,
        start_time,
        _ingested_at,
        participant_raw,
        participant_name,
        parsed_email,
        {{ nexus.validate_and_normalize_email('parsed_email') }} as normalized_email,
        role,
        display_name,
        is_self,
        CAST(NULL AS STRING) as response_status,
        CAST(NULL AS BOOL) as is_optional,
        CAST(NULL AS BOOL) as is_organizer
    FROM organizer_raw
    WHERE {{ nexus.validate_and_normalize_email('parsed_email') }} IS NOT NULL
),

-- Extract and normalize creator
creator_raw AS (
    SELECT
        event_id,
        ical_uid,
        calendar_event_id,
        instance_start,
        start_time,
        _ingested_at,
        JSON_EXTRACT_SCALAR(_raw_record, '$.creator.email') as participant_raw,
        {{ nexus.parse_gmail_email("JSON_EXTRACT_SCALAR(_raw_record, '$.creator.email')") }} as parsed_email,
        COALESCE(
            JSON_EXTRACT_SCALAR(_raw_record, '$.creator.displayName'),
            {{ nexus.extract_gmail_name("JSON_EXTRACT_SCALAR(_raw_record, '$.creator.email')") }}
        ) as participant_name,
        'creator' as role,
        JSON_EXTRACT_SCALAR(_raw_record, '$.creator.displayName') as display_name,
        CAST(NULL AS BOOL) as is_self,
        CAST(NULL AS STRING) as response_status,
        CAST(NULL AS BOOL) as is_optional,
        CAST(NULL AS BOOL) as is_organizer
    FROM source_data
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.creator.email') IS NOT NULL
      AND JSON_EXTRACT_SCALAR(_raw_record, '$.creator.email') != ''
),

creator_normalized AS (
    SELECT
        event_id,
        ical_uid,
        calendar_event_id,
        instance_start,
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
        s.event_id,
        s.ical_uid,
        s.calendar_event_id,
        s.instance_start,
        s.start_time,
        s._ingested_at,
        JSON_EXTRACT_SCALAR(attendee, '$.email') as participant_raw,
        {{ nexus.parse_gmail_email("JSON_EXTRACT_SCALAR(attendee, '$.email')") }} as parsed_email,
        COALESCE(
            JSON_EXTRACT_SCALAR(attendee, '$.displayName'),
            {{ nexus.extract_gmail_name("JSON_EXTRACT_SCALAR(attendee, '$.email')") }}
        ) as participant_name,
        'attendee' as role,
        JSON_EXTRACT_SCALAR(attendee, '$.displayName') as display_name,
        CAST(JSON_EXTRACT_SCALAR(attendee, '$.self') AS BOOL) as is_self,
        JSON_EXTRACT_SCALAR(attendee, '$.responseStatus') as response_status,
        CAST(JSON_EXTRACT_SCALAR(attendee, '$.optional') AS BOOL) as is_optional,
        CAST(JSON_EXTRACT_SCALAR(attendee, '$.organizer') AS BOOL) as is_organizer
    FROM source_data s,
    UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.attendees')) as {% if target.type == 'duckdb' %}t(attendee){% else %}attendee{% endif %}
    WHERE JSON_EXTRACT_SCALAR(attendee, '$.email') IS NOT NULL
      AND JSON_EXTRACT_SCALAR(attendee, '$.email') != ''
),

attendees_normalized AS (
    SELECT
        event_id,
        ical_uid,
        calendar_event_id,
        instance_start,
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
    event_id,
    ical_uid,
    calendar_event_id,
    instance_start,
    participant_raw,
    TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(participant_name, {% if target.type == 'bigquery' %}r'^[\'"]+'{% else %}'^[''"]+'{% endif %}, ''),
                {% if target.type == 'bigquery' %}r'[\'"]+$'{% else %}'[''"]+$'{% endif %},
                ''
            ),
            {% if target.type == 'bigquery' %}r'\s*\([^)]*@[^)]*\)\s*$'{% else %}'\s*\([^)]*@[^)]*\)\s*$'{% endif %},
            ''
        )
    ) as name,
    normalized_email as email,
    SPLIT(normalized_email, '@')[SAFE_OFFSET(1)] as domain,
    role,
    response_status,
    is_optional,
    is_organizer,
    start_time,
    _ingested_at
FROM participants_combined
{# The raw feed can repeat an attendee within one event (no dedup existed
   here historically); the merge needs one row per unique_key per batch. #}
{% if is_incremental() %}
QUALIFY row_number() OVER (PARTITION BY event_id, normalized_email, role ORDER BY _ingested_at DESC) = 1
{% endif %}
