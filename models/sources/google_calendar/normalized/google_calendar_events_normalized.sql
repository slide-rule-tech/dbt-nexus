{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['event_id']),
    unique_key='event_id',
    on_schema_change='append_new_columns',
    tags=['google_calendar', 'normalized']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'event_id']) }}

-- Normalized layer: Clean, deduplicated events with explicit columns
-- Extracts data from new STANDARD_TABLE_SCHEMA with _raw_record
-- Identity is Google's own event `id`, carried through from the base dedup
-- view as event_key. See macros/sources/google_calendar/
-- google_calendar_event_key.sql for why that replaced an iCalUID composite.
WITH source_data AS (
    SELECT
        _raw_record,
        event_key,
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
    {% if is_incremental() %}
      AND _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
    {% endif %}
),

extracted AS (
    SELECT
        -- Event identifiers
        null as calendar_id,
        calendar_event_id,
        ical_uid,
        event_key,

        -- Which series this occurrence belongs to (NULL for one-offs), read
        -- off the instance id so it survives both stripped payloads and series
        -- re-cuts.
        {{ nexus.google_calendar_series_id('_raw_record') }} as series_id,

        -- Which CUT of that series. Google reissues this as <master>_R<ts>
        -- when a series is re-cut, so it is the series version, not a stable
        -- series identity -- use series_id for the latter.
        JSON_EXTRACT_SCALAR(_raw_record, '$.recurringEventId') as recurring_event_id,

        -- Determine instanceStart for recurring events
        -- Priority: originalStartTime.dateTime > start.dateTime > start.date
        {{ nexus.google_calendar_instance_start('_raw_record') }} as instance_start,

        -- Google's own classification: default | outOfOffice | focusTime |
        -- workingLocation | birthday. 'default' is the only value that means
        -- "a meeting"; the rest are blocks and markers. Cheaper and more
        -- reliable than inferring it from attendees or titles.
        JSON_EXTRACT_SCALAR(_raw_record, '$.eventType') as calendar_event_type,

        -- Revision metadata. `sequence` is Google's own revision counter and
        -- `updated` the wall-clock of that revision -- together they order an
        -- occurrence's versions, which _ingested_at cannot do (it records when
        -- we synced, not when the change was made). Replaying them against
        -- start_time is what tells you whether a meeting was still on the
        -- calendar when its time arrived.
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.sequence') AS {% if target.type == 'bigquery' %}INT64{% else %}BIGINT{% endif %}) as sequence_number,
        {% if target.type == 'bigquery' %}SAFE_CAST{% else %}try_cast{% endif %}(JSON_EXTRACT_SCALAR(_raw_record, '$.updated') AS TIMESTAMP) as updated_at,
        {% if target.type == 'bigquery' %}SAFE_CAST{% else %}try_cast{% endif %}(JSON_EXTRACT_SCALAR(_raw_record, '$.created') AS TIMESTAMP) as created_at,

        -- Event details
        JSON_EXTRACT_SCALAR(_raw_record, '$.summary') as summary,
        JSON_EXTRACT_SCALAR(_raw_record, '$.description') as description,
        JSON_EXTRACT_SCALAR(_raw_record, '$.location') as location,
        JSON_EXTRACT_SCALAR(_raw_record, '$.status') as status,
        
        -- Parse start and end times
        {% if target.type == 'bigquery' %}SAFE_CAST(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            ) AS TIMESTAMP){% else %}try_cast(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            ) AS TIMESTAMP){% endif %} as start_time,
        
        {% if target.type == 'bigquery' %}SAFE_CAST(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.end.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.end.date'), 'T23:59:59Z')
            ) AS TIMESTAMP){% else %}try_cast(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.end.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.end.date'), 'T23:59:59Z')
            ) AS TIMESTAMP){% endif %} as end_time,
        
        -- Check if it's all day event
        CASE 
            WHEN JSON_EXTRACT_SCALAR(_raw_record, '$.start.date') IS NOT NULL THEN true
            ELSE false
        END as is_all_day,
        
        -- Descriptive only -- nothing keys off this any more.
        {{ nexus.google_calendar_is_recurring('_raw_record') }} as is_recurring,
        
        -- Determine if meeting has external attendees (for event classification)
        (
            SELECT COUNT(*) > 0
            FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.attendees')) as attendee
            WHERE JSON_EXTRACT_SCALAR(attendee, '$.email') IS NOT NULL
              AND {% if target.type == 'bigquery' %}REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(attendee, '$.email'), r'@(.+)'){% else %}regexp_extract(JSON_EXTRACT_SCALAR(attendee, '$.email'), '@(.+)', 1){% endif %} NOT IN (
                  {%- for domain in var('internal_domains', []) -%}
                  '{{ domain }}'
                  {%- if not loop.last -%},{%- endif -%}
                  {%- endfor -%}
              )
        ) OR (
            JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email') IS NOT NULL
            AND {% if target.type == 'bigquery' %}REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email'), r'@(.+)'){% else %}regexp_extract(JSON_EXTRACT_SCALAR(_raw_record, '$.organizer.email'), '@(.+)', 1){% endif %} NOT IN (
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

-- Version replay, for meeting_status below.
--
-- Reads the base view (EVERY version ever ingested) rather than the dedup,
-- because the whole point is the history the dedup discards. Google stamps each
-- version with `sequence` (its own revision counter) and `updated` (when that
-- revision was made); ordering by those recovers the sequence of edits, which
-- _ingested_at cannot do -- it records when we synced, not when the change
-- happened.
version_history AS (
    SELECT
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') AS event_key,
        JSON_EXTRACT_SCALAR(_raw_record, '$.status') AS status,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.sequence') AS {% if target.type == 'bigquery' %}INT64{% else %}BIGINT{% endif %}) AS sequence_number,
        {% if target.type == 'bigquery' %}SAFE_CAST{% else %}try_cast{% endif %}(JSON_EXTRACT_SCALAR(_raw_record, '$.updated') AS TIMESTAMP) AS updated_at,
        {% if target.type == 'bigquery' %}SAFE_CAST(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            ) AS TIMESTAMP){% else %}try_cast(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            ) AS TIMESTAMP){% endif %} AS start_time,
        _ingested_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
),

-- The last version written at or before the occurrence's start time: what the
-- calendar said when the slot actually arrived.
status_at_start AS (
    SELECT event_key, status AS status_when_slot_arrived
    FROM version_history
    WHERE updated_at <= start_time
    QUALIFY row_number() OVER (
        PARTITION BY event_key
        ORDER BY sequence_number DESC, updated_at DESC, _ingested_at DESC
    ) = 1
)

SELECT
    event_key as event_id,
    calendar_id,
    ical_uid,
    calendar_event_id,
    series_id,
    recurring_event_id,
    instance_start,
    summary,
    description,
    location,
    status,

    -- Did this meeting happen? A calendar is a plan, so a past-dated event is
    -- not evidence on its own -- a series retired months ago still leaves
    -- instances on every date it used to cover. `status` alone only says what
    -- the calendar reads NOW; replaying the versions says what it read when the
    -- slot arrived, which is the closest observable proxy.
    --
    -- Exact-vs-observed: 'occurred' means "still on the calendar when its time
    -- came", NOT "humans attended". Attendee responseStatus is available in
    -- google_calendar_event_participants for anyone who needs to go further.
    --
    -- coalesce: an occurrence with no version written before its start time
    -- (created retroactively, or first synced after the fact) has no replay
    -- row; fall back to its current status.
    CASE
        WHEN start_time > current_timestamp()
            THEN CASE WHEN status = 'confirmed' THEN 'scheduled' ELSE 'cancelled' END
        WHEN COALESCE(status_when_slot_arrived, status) = 'confirmed' THEN 'occurred'
        ELSE 'cancelled'
    END as meeting_status,

    calendar_event_type,
    sequence_number,
    updated_at,
    created_at,
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
FROM extracted
LEFT JOIN status_at_start USING (event_key)
-- Belt-and-braces: the base dedup view already reduces to one row per
-- event_key, but an incremental batch can still carry two versions of the same
-- occurrence (a re-synced record inside the lookback window), and the merge
-- rejects duplicate keys within one batch.
QUALIFY row_number() OVER (PARTITION BY event_key ORDER BY _ingested_at DESC) = 1
