{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='view',
    tags=['google_calendar', 'base']
) }}

-- Base dedup: one row per calendar occurrence, plus the one verdict only this
-- layer can compute -- is the occurrence cancelled on EVERY calendar we sync?
--
-- The occurrence key is Google's own `id`, verbatim. See
-- macros/sources/google_calendar/google_calendar_event_key.sql for why that
-- replaced an iCalUID-derived composite key, and why `id` is stable under
-- rescheduling, instance drags and series re-cuts.
--
-- WHY CANCELLATION IS A CROSS-CALENDAR QUESTION
--
--   One event `id` is shared by every attendee's copy of an invite, so "is
--   this meeting cancelled" and "is this meeting still on X's calendar" are
--   different questions that read identically on a single copy. Google
--   overloads `status: cancelled` across both -- an organizer calling the
--   meeting off, one attendee deleting their copy, a skipped series instance,
--   an uninvite -- and nothing in the payload distinguishes them. Only the
--   population of copies can: the occurrence is CANCELLED iff every calendar's
--   latest version says cancelled, and one live copy anywhere keeps it a real
--   upcoming meeting. In the largest workspace we sync, 8,432 occurrences are
--   exactly that case -- cancelled on some calendars, held live on others.
--
-- WHICH CLOCK ORDERS A CALENDAR'S VERSIONS
--
--   Never `_ingested_at` -- that is our sync clock, and backfills and
--   re-syncs reorder it freely. Google gives two of its own:
--
--     `updated`   wall-clock of the revision. The best signal, but absent on
--                 most deletion tombstones (a deleted object has no
--                 modification time to report).
--     `etag`      present on EVERY record, tombstones included, and increases
--                 with `updated` on 99.96% of comparable version pairs.
--
--   So: compare by `updated` when both versions carry it, by `etag`
--   otherwise. Concretely, the max-etag version wins when it is undated (a
--   tombstone that arrived after the last full record -- 169,824 of the
--   170,588 cases where the clocks disagree), else the max-`updated` dated
--   version wins (which also corrects the 754 pairs where etag regresses
--   against `updated`). The naive "updated DESC NULLS LAST" ordering silently
--   reintroduces the original bug: a dated record then outranks every
--   tombstone forever, and a deletion can never take effect.
--
-- ROOM AND GROUP CALENDARS ARE IGNORED ENTIRELY
--
--   Rooms (`...@resource.calendar.google.com`) mirror bookings; they are not
--   participants, and their copies should neither hold a meeting live nor
--   vote it cancelled.
--
--   Group calendars (`...@group.calendar.google.com`, including Google's
--   `group.v` holiday/birthday calendars) are the same kind of non-person:
--   a hold that exists only on a shared calendar is not a meeting, and a
--   real invite that a person is on already lives on that person's
--   calendar. Counting them lets a stale or test group calendar keep an
--   occurrence "live" after every person has dropped it. Import and
--   personal calendars still count, stale ones too: a calendar that
--   stopped syncing still holds a true last-known state.

WITH source_data AS (
    SELECT
        *,
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') AS event_key,
        -- The calendar this copy was read from. Google puts calendarId in the
        -- request path, never in the item, so only the caller knows it: the
        -- ingestion handler stamps `_calendar_id` onto each record, and
        -- `_stream_id` is the envelope's copy of the same value for rows
        -- landed before that.
        COALESCE(
            JSON_EXTRACT_SCALAR(_raw_record, '$._calendar_id'),
            _stream_id
        ) AS calendar_key,
        JSON_EXTRACT_SCALAR(_raw_record, '$.status') AS version_status,
        -- Google's revision counter, parsed out of its quoted-string etag.
        {% if target.type == 'bigquery' %}
        SAFE_CAST(REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(_raw_record, '$.etag'), r'(\d+)') AS INT64)
        {% else %}
        try_cast(regexp_extract(JSON_EXTRACT_SCALAR(_raw_record, '$.etag'), '(\d+)', 1) AS BIGINT)
        {% endif %} AS etag_num,
        {% if target.type == 'bigquery' %}SAFE_CAST{% else %}try_cast{% endif %}(
            JSON_EXTRACT_SCALAR(_raw_record, '$.updated') AS TIMESTAMP
        ) AS updated_at,
        -- A stripped payload: no eventType, summary or attendees. Never a
        -- usable record on its own -- deletion stubs even carry placeholder
        -- 1999/2000 start and end dates that must never win the payload.
        JSON_EXTRACT_SCALAR(_raw_record, '$.eventType') IS NULL AS is_tombstone
    FROM {{ ref('google_calendar_events_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
      AND COALESCE(
              JSON_EXTRACT_SCALAR(_raw_record, '$._calendar_id'),
              _stream_id
          ) NOT LIKE '%resource.calendar.google.com'
      AND COALESCE(
              JSON_EXTRACT_SCALAR(_raw_record, '$._calendar_id'),
              _stream_id
          ) NOT LIKE '%group.calendar.google.com'
      AND COALESCE(
              JSON_EXTRACT_SCALAR(_raw_record, '$._calendar_id'),
              _stream_id
          ) NOT LIKE '%group.v.calendar.google.com'
),

versioned AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY event_key, calendar_key
            ORDER BY etag_num DESC
        ) AS rn_by_etag,
        -- Dated versions first, then by `updated`; etag breaks exact ties.
        ROW_NUMBER() OVER (
            PARTITION BY event_key, calendar_key
            ORDER BY
                CASE WHEN updated_at IS NULL THEN 1 ELSE 0 END ASC,
                updated_at DESC,
                etag_num DESC
        ) AS rn_by_updated
    FROM source_data
),

-- One verdict per (occurrence, calendar): what its latest version says.
calendar_verdicts AS (
    SELECT
        event_key,
        calendar_key,
        CASE
            -- Newest version by etag is undated: a tombstone after the last
            -- full record. It wins -- `updated` cannot arbitrate a version
            -- that has none.
            WHEN MAX(CASE WHEN rn_by_etag = 1 AND updated_at IS NULL THEN 1 ELSE 0 END) = 1
                THEN MAX(CASE WHEN rn_by_etag = 1 THEN version_status END)
            -- Otherwise the newest DATED version by Google's wall clock.
            ELSE MAX(CASE WHEN rn_by_updated = 1 THEN version_status END)
        END AS latest_status
    FROM versioned
    GROUP BY 1, 2
),

event_verdicts AS (
    SELECT
        event_key,
        MIN(CASE WHEN latest_status = 'cancelled' THEN 1 ELSE 0 END) = 1
            AS all_calendars_cancelled
    FROM calendar_verdicts
    GROUP BY 1
),

deduplicated AS (
    SELECT
        source_data.*,
        event_verdicts.all_calendars_cancelled,
        -- The PAYLOAD winner, which is a different contest from the verdict:
        --   1. full records outrank tombstones, so a stripped payload (and its
        --      fake 1999 dates) can never clobber summary/attendees;
        --   2. while the occurrence is live anywhere, a live copy outranks a
        --      cancelled one, so the payload reflects the meeting as it
        --      stands for the calendars still holding it;
        --   3. then Google's clock, dated versions first.
        ROW_NUMBER() OVER (
            PARTITION BY source_data.event_key
            ORDER BY
                source_data.is_tombstone ASC,
                CASE
                    WHEN NOT event_verdicts.all_calendars_cancelled
                         AND source_data.version_status = 'cancelled'
                    THEN 1 ELSE 0
                END ASC,
                CASE WHEN source_data.updated_at IS NULL THEN 1 ELSE 0 END ASC,
                source_data.updated_at DESC,
                source_data.etag_num DESC
        ) AS rn,
        -- Watermark plumbing, NOT semantics: incremental consumers batch on
        -- _ingested_at, and the payload winner for a cancelled-everywhere
        -- occurrence is an old full record that would sit below the watermark
        -- while a fresh tombstone flips the verdict. Advancing the row to the
        -- occurrence's newest arrival is what puts it back in the next batch.
        MAX(source_data._ingested_at) OVER (
            PARTITION BY source_data.event_key
        ) AS latest_ingested_at
    FROM source_data
    JOIN event_verdicts USING (event_key)
)

SELECT
    event_key,
    latest_ingested_at AS _ingested_at,
    all_calendars_cancelled,
    _connection_id,
    _stream_id,
    _raw_record,
    _sync_id,
    _account,
    _sync_metadata
FROM deduplicated
WHERE rn = 1
  -- Drop occurrences that only ever arrived as tombstones: no title, no
  -- attendees, nobody to attribute them to. (An occurrence with a full record
  -- AND later tombstones everywhere is kept -- it is a real meeting that was
  -- cancelled, and all_calendars_cancelled says so.)
  AND NOT is_tombstone
