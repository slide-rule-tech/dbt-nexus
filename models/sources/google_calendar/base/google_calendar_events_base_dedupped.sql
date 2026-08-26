{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='view',
    tags=['google_calendar', 'base']
) }}

-- Base dedup: one row per calendar occurrence, latest version wins.
--
-- The key comes from nexus.google_calendar_event_key so this model, the
-- normalized model and the participants model cannot drift apart; it also
-- strips the _R<timestamp> suffix Google issues when a recurring series is
-- re-cut, which previously split one occurrence across two or three keys that
-- disagreed about `status`. See the macro for the full story.
--
-- event_key is emitted here so downstream models select it rather than
-- rebuilding it from _raw_record.
WITH source_data AS (
    SELECT
        *,
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') AS calendar_event_id,
        JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') AS ical_uid,
        {{ nexus.google_calendar_instance_start('_raw_record') }} AS instance_start,
        -- A deletion tombstone: Google returns {id, status:"cancelled"} with
        -- the payload stripped -- no summary, no attendees, no eventType,
        -- sequence or updated. Never a usable event on its own.
        JSON_EXTRACT_SCALAR(_raw_record, '$.eventType') IS NULL AS is_tombstone,
        {{ nexus.google_calendar_is_recurring('_raw_record') }} AS is_recurring
    FROM {{ ref('google_calendar_events_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
      AND JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') IS NOT NULL
),

with_event_key AS (
    SELECT
        *,
        {{ nexus.google_calendar_event_key('ical_uid', 'instance_start') }} AS event_key
    FROM source_data
    WHERE ical_uid IS NOT NULL
),

deduplicated AS (
    SELECT
        *,
        -- Full records outrank tombstones so a stripped payload can never
        -- clobber summary/attendees. On today's data the two never share a key
        -- (an uid-less tombstone is already filtered above), so this only
        -- matters if Google starts emitting tombstones that carry a uid.
        ROW_NUMBER() OVER (
            PARTITION BY event_key
            ORDER BY is_tombstone ASC, _ingested_at DESC
        ) AS rn
    FROM with_event_key
    WHERE event_key IS NOT NULL
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
