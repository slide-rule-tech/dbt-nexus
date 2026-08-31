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
        all_calendars_cancelled,
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

        -- WHICH CALENDAR this copy was read from -- not which event it is.
        --
        -- One Google event `id` is shared by every attendee's copy of an
        -- invite, so a row is really (occurrence, calendar). Losing the
        -- calendar is what makes a per-attendee fact inexpressible: when one
        -- person removes a meeting from their calendar their copy comes back
        -- `cancelled` while everyone else's stays `confirmed`, and nothing in
        -- the payload distinguishes that from the meeting itself being called
        -- off. Only comparing calendars can.
        --
        -- Google never puts calendarId in the item -- it lives in the request
        -- path -- so only the caller knows it. `_calendar_id` is stamped on by
        -- the ingestion handler for exactly that reason; `_stream_id` is the
        -- envelope's copy of the same value and covers every row landed before
        -- that. Verified equal to Google's own `self` attendee on 315,402 of
        -- 315,738 copies with zero mismatches (the remainder being copies
        -- where Google marked no attendee as self).
        --
        -- CAVEAT: this model is one row per OCCURRENCE, and the dedup picks
        -- one winning copy (a live calendar's, while the occurrence is live
        -- anywhere). So this names the copy you are looking at; it is not
        -- "the calendars this meeting is on" -- that question needs a row per
        -- (occurrence, calendar).
        COALESCE(
            JSON_EXTRACT_SCALAR(_raw_record, '$._calendar_id'),
            _stream_id
        ) as calendar_id,
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
        -- Status under the cross-calendar rule: an occurrence is cancelled
        -- IFF every synced calendar's latest version says cancelled (rooms
        -- excluded; see google_calendar_events_base_dedupped). One live copy
        -- anywhere keeps it a real meeting, so a copy-level `cancelled` --
        -- which can just mean one attendee dropped it -- never leaks through
        -- as the meeting's status. The dedup view also prefers a live copy's
        -- payload while the occurrence is live, so the ELSE branch reads the
        -- status of a calendar that still holds it.
        CASE
            WHEN all_calendars_cancelled THEN 'cancelled'
            ELSE JSON_EXTRACT_SCALAR(_raw_record, '$.status')
        END as status,
        
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
        COALESCE(
            JSON_EXTRACT_SCALAR(_raw_record, '$._calendar_id'),
            _stream_id
        ) AS calendar_key,
        JSON_EXTRACT_SCALAR(_raw_record, '$.status') AS status,
        {% if target.type == 'bigquery' %}
        SAFE_CAST(REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(_raw_record, '$.etag'), r'(\d+)') AS INT64)
        {% else %}
        try_cast(regexp_extract(JSON_EXTRACT_SCALAR(_raw_record, '$.etag'), '(\d+)', 1) AS BIGINT)
        {% endif %} AS etag_num,
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
      AND COALESCE(
              JSON_EXTRACT_SCALAR(_raw_record, '$._calendar_id'),
              _stream_id
          ) NOT LIKE '%resource.calendar.google.com'
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
),

-- Was the occurrence cancelled on EVERY calendar by the time its slot
-- arrived? The dated replay above cannot answer this: deletion tombstones
-- carry no `updated`, so a meeting deleted everywhere before its start is
-- invisible to it and would replay as "still on the calendar".
--
-- A version counts as evidence-before-start when
--   dated:    `updated` <= start (Google's clock, as in the replay), or
--   undated:  `_ingested_at` <= start. This is NOT _ingested_at used as an
--             ordering -- it is an existence bound: we OBSERVED the tombstone
--             before the slot arrived, so that calendar had dropped the
--             meeting by then. A tombstone first seen after start proves
--             nothing about before (people delete old meetings that DID
--             happen), so it is excluded and the meeting keeps `occurred`.
--
-- Within the evidence, each calendar's as-of verdict uses the same clock rule
-- as the dedup view: an undated max-etag version (a tombstone after the last
-- full record) wins, else the max-`updated` dated version.
as_of_versions AS (
    SELECT
        version_history.*,
        occ.start_time AS occ_start
    FROM version_history
    JOIN (SELECT event_key, start_time FROM extracted) occ USING (event_key)
    WHERE (version_history.updated_at IS NOT NULL
           AND version_history.updated_at <= occ.start_time)
       OR (version_history.updated_at IS NULL
           AND version_history._ingested_at <= occ.start_time)
),

as_of_ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY event_key, calendar_key
            ORDER BY etag_num DESC
        ) AS rn_by_etag,
        ROW_NUMBER() OVER (
            PARTITION BY event_key, calendar_key
            ORDER BY
                CASE WHEN updated_at IS NULL THEN 1 ELSE 0 END ASC,
                updated_at DESC,
                etag_num DESC
        ) AS rn_by_updated
    FROM as_of_versions
),

as_of_verdicts AS (
    SELECT
        event_key,
        calendar_key,
        CASE
            WHEN MAX(CASE WHEN rn_by_etag = 1 AND updated_at IS NULL THEN 1 ELSE 0 END) = 1
                THEN MAX(CASE WHEN rn_by_etag = 1 THEN status END)
            ELSE MAX(CASE WHEN rn_by_updated = 1 THEN status END)
        END AS status_as_of_start
    FROM as_of_ranked
    GROUP BY 1, 2
),

cancelled_by_start AS (
    SELECT
        event_key,
        MIN(CASE WHEN status_as_of_start = 'cancelled' THEN 1 ELSE 0 END) = 1
            AS was_cancelled_by_start
    FROM as_of_verdicts
    GROUP BY 1
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
        -- Cancelled everywhere before the slot arrived: it did not happen,
        -- however confident the dated replay is -- tombstone deletions are
        -- invisible to `updated` and live only in this branch.
        WHEN COALESCE(was_cancelled_by_start, FALSE) THEN 'cancelled'
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
LEFT JOIN cancelled_by_start USING (event_key)
-- Belt-and-braces: the base dedup view already reduces to one row per
-- event_key, but an incremental batch can still carry two versions of the same
-- occurrence (a re-synced record inside the lookback window), and the merge
-- rejects duplicate keys within one batch.
QUALIFY row_number() OVER (PARTITION BY event_key ORDER BY _ingested_at DESC) = 1
