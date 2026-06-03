{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='view',
    tags=['google_calendar', 'base']
) }}

WITH source_data AS (
    SELECT
        *,
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') AS calendar_event_id,
        JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') AS ical_uid,
        -- ISO 8601 with fractional seconds + tz offset. BQ needs
        -- PARSE_TIMESTAMP with %E*S/%Ez format codes (duck strptime
        -- doesn't recognize). try_cast on both adapters auto-detects
        -- ISO 8601 and is equivalent for this format.
        {% if target.type == 'bigquery' %}SAFE_CAST(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.originalStartTime.dateTime'),
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            ) AS TIMESTAMP){% else %}try_cast(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.originalStartTime.dateTime'),
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            ) AS TIMESTAMP){% endif %} AS instance_start,
        CASE
            WHEN JSON_EXTRACT_SCALAR(_raw_record, '$.recurringEventId') IS NOT NULL THEN TRUE
            WHEN JSON_EXTRACT_ARRAY(_raw_record, '$.recurrence') IS NOT NULL
                 AND ARRAY_LENGTH(JSON_EXTRACT_ARRAY(_raw_record, '$.recurrence')) > 0 THEN TRUE
            ELSE FALSE
        END AS is_recurring
    FROM {{ ref('google_calendar_events_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
      AND JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') IS NOT NULL
),

with_event_key AS (
    SELECT
        *,
        CASE
            WHEN is_recurring THEN CONCAT(ical_uid, '|', CAST(instance_start AS {% if target.type == 'bigquery' %}STRING{% else %}VARCHAR{% endif %}))
            ELSE ical_uid
        END AS event_key
    FROM source_data
    WHERE ical_uid IS NOT NULL
),

deduplicated AS (
    SELECT
        _ingested_at,
        _connection_id,
        _stream_id,
        _raw_record,
        _sync_id,
        _account,
        _sync_metadata,
        ROW_NUMBER() OVER (
            PARTITION BY event_key
            ORDER BY _ingested_at DESC
        ) AS rn
    FROM with_event_key
    WHERE event_key IS NOT NULL
)

SELECT
    _ingested_at,
    _connection_id,
    _stream_id,
    _raw_record,
    _sync_id,
    _account,
    _sync_metadata
FROM deduplicated
WHERE rn = 1

