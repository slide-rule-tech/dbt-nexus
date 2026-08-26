{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'dimensions']
) }}

-- Dimensions on calendar events.
--
-- meeting_status: scheduled | occurred | cancelled
--   A calendar is a plan, so a past-dated event is not evidence a meeting
--   happened -- a recurring series retired months ago still leaves instances
--   sitting on every future date it used to cover. What distinguishes them is
--   the append-only raw history: Google stamps every version of an occurrence
--   with `sequence` (its own revision counter) and `updated` (when that
--   revision was made). Replaying an occurrence's versions and taking the last
--   one written at or before start_time recovers what the calendar said at the
--   moment the slot arrived, which is the closest observable proxy for "did
--   this happen".
--
--   Note this is exact-vs-observed: it means "still on the calendar when its
--   time came", not "humans attended". Attendee responseStatus lives in
--   google_calendar_event_participants for anyone who needs to go further.
--
-- is_series: true when the occurrence belongs to a recurring series.
--   Emitted only when true -- the is_ prefix makes nexus_event_dimensions
--   pivot it to BOOLEAN with COALESCE(..., FALSE), so absence IS false and a
--   'false' row would be wrong.

with versions_raw as (

    -- Every version ever ingested, not the deduped view: the point is the
    -- history the dedup throws away.
    select
        JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') as ical_uid,
        {{ nexus.google_calendar_instance_start('_raw_record') }} as instance_start,
        JSON_EXTRACT_SCALAR(_raw_record, '$.status') as status,
        SAFE_CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.sequence') AS {% if target.type == 'bigquery' %}INT64{% else %}BIGINT{% endif %}) as sequence_number,
        {% if target.type == 'bigquery' %}SAFE_CAST{% else %}try_cast{% endif %}(JSON_EXTRACT_SCALAR(_raw_record, '$.updated') AS TIMESTAMP) as updated_at,
        {% if target.type == 'bigquery' %}SAFE_CAST(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            ) AS TIMESTAMP){% else %}try_cast(COALESCE(
                JSON_EXTRACT_SCALAR(_raw_record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(_raw_record, '$.start.date'), 'T00:00:00Z')
            ) AS TIMESTAMP){% endif %} as start_time,
        {{ nexus.google_calendar_is_recurring('_raw_record') }} as is_recurring,
        _ingested_at
    from {{ ref('google_calendar_events_base') }}
    where JSON_EXTRACT_SCALAR(_raw_record, '$.id') is not null
      and JSON_EXTRACT_SCALAR(_raw_record, '$.iCalUID') is not null
),

versions as (
    select
        {{ nexus.google_calendar_event_key('ical_uid', 'instance_start') }} as event_key,
        versions_raw.*
    from versions_raw
),

-- What the calendar said when the slot arrived. Ordered by Google's own
-- revision metadata rather than _ingested_at, which records when we synced,
-- not when the change was made.
at_start as (
    select * from versions
    where updated_at <= start_time
    qualify row_number() over (
        partition by event_key
        order by sequence_number desc, updated_at desc, _ingested_at desc
    ) = 1
),

-- Current state, for occurrences whose start time is still in the future.
latest as (
    select * from versions
    qualify row_number() over (
        partition by event_key
        order by _ingested_at desc
    ) = 1
),

series_flag as (
    select event_key, logical_or(is_recurring) as is_series
    from versions
    group by event_key
),

-- Join through the event model so event_id is the hashed id the event log
-- uses, and so tombstone-only / start-less occurrences (already dropped
-- upstream) never acquire dimensions.
resolved as (
    select
        e.event_id,
        e.occurred_at,
        e._ingested_at,
        coalesce(s.is_series, false) as is_series,
        case
            when e.start_time > current_timestamp() then
                case when l.status = 'confirmed' then 'scheduled' else 'cancelled' end
            -- coalesce: an occurrence with no version written before its start
            -- time (created retroactively, or first synced after the fact)
            -- has no at_start row; fall back to its current state.
            when coalesce(a.status, l.status) = 'confirmed' then 'occurred'
            else 'cancelled'
        end as meeting_status
    from {{ ref('google_calendar_event_events') }} e
    left join at_start    a on a.event_key = e.calendar_event_key
    left join latest      l on l.event_key = e.calendar_event_key
    left join series_flag s on s.event_key = e.calendar_event_key
),

meeting_status_dimensions as (
    select
        {{ nexus.create_nexus_id('event_dimension', ['event_id', "'meeting_status'"]) }}
            as event_dimension_id,
        event_id,
        'meeting_status' as dimension_name,
        meeting_status as dimension_value,
        occurred_at,
        'google_calendar' as source,
        -- Required by process_event_dimensions since dbt-nexus v0.13: the
        -- unioned model uses _ingested_at as its incremental watermark and
        -- partition key. Stamped from the event's own ingestion clock.
        _ingested_at
    from resolved
),

is_series_dimensions as (
    select
        {{ nexus.create_nexus_id('event_dimension', ['event_id', "'is_series'"]) }}
            as event_dimension_id,
        event_id,
        'is_series' as dimension_name,
        'true' as dimension_value,
        occurred_at,
        'google_calendar' as source,
        _ingested_at
    from resolved
    where is_series
)

select * from meeting_status_dimensions
union all
select * from is_series_dimensions
