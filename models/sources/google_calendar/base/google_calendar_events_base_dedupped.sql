{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='view',
    tags=['google_calendar', 'base']
) }}

-- Base dedup: one row per calendar occurrence, latest version wins.
--
-- The occurrence key is Google's own `id`, verbatim. See
-- macros/sources/google_calendar/google_calendar_event_key.sql for why that
-- replaced an iCalUID-derived composite key, and why `id` is stable under
-- rescheduling, instance drags and series re-cuts.
--
-- event_key is emitted so downstream models select it rather than re-deriving
-- identity from _raw_record.
WITH source_data AS (
    SELECT
        *,
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') AS event_key,
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') AS calendar_event_id,
        JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') AS ical_uid,
        {{ nexus.google_calendar_instance_start('_raw_record') }} AS instance_start,
        -- A deletion tombstone: Google returns {id, status:"cancelled"} with
        -- the payload stripped -- no summary, no attendees, no eventType,
        -- sequence or updated. Never a usable event on its own.
        JSON_EXTRACT_SCALAR(_raw_record, '$.eventType') IS NULL AS is_tombstone
    FROM {{ ref('google_calendar_events_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
),

signalled AS (
    SELECT
        *,
        -- When each KIND of signal last arrived for this occurrence. A
        -- tombstone carries no payload, so it cannot be the winning row -- but
        -- it is still the most recent thing Google told us, and that has to
        -- survive the dedup somehow. These two are how.
        MAX(IF(is_tombstone, _ingested_at, NULL)) OVER (
            PARTITION BY event_key
        ) AS last_tombstone_at,
        MAX(IF(NOT is_tombstone, _ingested_at, NULL)) OVER (
            PARTITION BY event_key
        ) AS last_full_at
    FROM source_data
),

deduplicated AS (
    SELECT
        *,
        -- Full records outrank tombstones so a stripped payload can never
        -- clobber summary/attendees. See is_deleted below for why that
        -- ordering does NOT mean a deletion is ignored.
        ROW_NUMBER() OVER (
            PARTITION BY event_key
            ORDER BY is_tombstone ASC, _ingested_at DESC
        ) AS rn,

        -- The occurrence is GONE FROM THE CALENDAR WE SYNC: the newest signal
        -- Google sent for it was a tombstone.
        --
        -- Read that literally, because Google overloads `cancelled` across
        -- four different real-world events and does not distinguish them:
        --   - the event was deleted outright,
        --   - one occurrence of a series was deleted or skipped,
        --   - the series was re-cut or shortened, so old instances cease to
        --     exist,
        --   - the syncing account was UNINVITED -- the meeting still happens
        --     for everyone else, it is simply no longer on this calendar.
        -- A tombstone carrying `recurringEventId` is an instance-level
        -- cancellation and one without it is a standalone event, but the last
        -- case is not recoverable from the tombstone at all. So this means
        -- "not on our calendar any more", never "this meeting did not happen"
        -- -- which is also why meeting_status keeps its version replay.
        --
        -- This exists because the ordering above, on its own, made deletion
        -- unobservable. A tombstone can never win the row, so an occurrence
        -- deleted in Google kept serving its last full record and read
        -- `confirmed` forever -- 15,428 occurrences in one workspace, 42% of
        -- the calendar, including meetings that a downstream consumer would
        -- happily treat as upcoming.
        --
        -- Note what this is NOT: a cancellation delivered as a FULL record
        -- (Google sends those too, with the payload intact) is not a tombstone
        -- and never was affected -- it sorts normally by _ingested_at and its
        -- status is simply read off the record.
        --
        -- `>=` not `>`: a tombstone and a full record ingested in the same
        -- batch carry the same timestamp, and the tombstone is the later fact.
        last_tombstone_at IS NOT NULL
            AND (last_full_at IS NULL OR last_tombstone_at >= last_full_at)
            AS is_deleted
    FROM signalled
)

SELECT
    event_key,

    -- The latest signal of ANY kind, not the winning row's own timestamp.
    --
    -- Load-bearing for incremental consumers. The winning row for a deleted
    -- occurrence is an OLD full record, so with its original timestamp the
    -- occurrence would sit below the watermark and its `is_deleted` would
    -- never reach the incremental model -- the deletion would be computed
    -- correctly here and then silently never applied. Advancing it to the
    -- tombstone's arrival is what puts the occurrence back in the next batch.
    GREATEST(_ingested_at, COALESCE(last_tombstone_at, _ingested_at))
        AS _ingested_at,

    is_deleted,
    _connection_id,
    _stream_id,
    _raw_record,
    _sync_id,
    _account,
    _sync_metadata
FROM deduplicated
WHERE rn = 1
  -- Drop occurrences that only ever arrived as tombstones: no title, no
  -- attendees, nobody to attribute them to. They would be contentless rows in
  -- the event log. (An occurrence with a full record AND a later tombstone is
  -- kept -- it is a real meeting that was deleted, and is_deleted says so.)
  AND NOT is_tombstone
