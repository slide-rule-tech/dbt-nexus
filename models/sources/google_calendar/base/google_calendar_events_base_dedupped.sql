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

deduplicated AS (
    SELECT
        *,
        -- Full records outrank tombstones so a stripped payload can never
        -- clobber summary/attendees.
        ROW_NUMBER() OVER (
            PARTITION BY event_key
            ORDER BY is_tombstone ASC, _ingested_at DESC
        ) AS rn
    FROM source_data
)

SELECT
    event_key,
    _ingested_at,
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
  -- the event log.
  AND NOT is_tombstone
