{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'dimensions']
) }}

-- Dimensions extracted from Google Calendar events.
--
-- google_calendar_event_id: the calendar occurrence this event is about.
--
-- On its face this looks redundant -- the calendar source obviously knows its
-- own event id, and carries it as a column already. The point is not this
-- source. It is that ANOTHER source observing the same meeting (a notes tool, a
-- transcription service, a CRM) can emit the same dimension name carrying a
-- copy of this id, and the two become joinable through nexus_event_dimensions
-- without either side knowing anything about the other's schema. The dimension
-- is the shared namespace where the two sources meet; a column on
-- google_calendar_events is invisible to them.
--
-- CORRELATING vs CLASSIFYING. Most dimensions classify -- is_revenue_earned,
-- business_unit -- and answer "what kind of event is this". Those should stay
-- few and business-meaningful. This one correlates: it answers "which record is
-- this event about". Correlating dimensions grow one per correlatable record
-- type, and that growth is correct rather than clutter. Same table, same
-- mechanics, different governance -- worth knowing before applying the
-- "keep the list short" rule to the wrong set.
--
-- NAMING. Named for the system that MINTS the id, never for the event carrying
-- it. `source` already says which system emitted the row; the dimension name
-- says which record it points at. A relative name (source_record_id) collapses
-- those two facts and reads backwards on the satellite side, where it would
-- suggest that source's own record id rather than the calendar id it holds.
-- The name is also what namespaces the value: a google_calendar_event_id of
-- '12345' cannot be confused with a shopify_order_id of '12345', so values need
-- no prefixing.
--
-- Deliberately NOT a dimension: meeting_status and is_recurring. Those are
-- single-source facts about a calendar event, answerable without any
-- cross-source reasoning, and they live as columns on the event. Promoting them
-- here would fail the cross-source test the dimensions docs set out.

WITH calendar_events AS (
    SELECT * FROM {{ ref('google_calendar_event_events') }}
),

calendar_event_id_dimensions AS (
    SELECT
        {{ nexus.create_nexus_id('event_dimension', ['event_id', "'google_calendar_event_id'"]) }}
            as event_dimension_id,
        event_id,
        'google_calendar_event_id' as dimension_name,
        -- The RAW Google event id, as minted by Google. Stable across
        -- attendees, and the only form a satellite source can assert
        -- independently -- see the identity note in
        -- macros/sources/google_calendar/google_calendar_event_key.sql.
        calendar_event_id as dimension_value,
        occurred_at,
        'google_calendar' as source,
        -- Required by process_event_dimensions since dbt-nexus v0.13: the
        -- unioned model uses _ingested_at as its incremental watermark and
        -- partition key. Stamped from the event's own ingestion clock.
        _ingested_at
    FROM calendar_events
    WHERE calendar_event_id IS NOT NULL
)

SELECT * FROM calendar_event_id_dimensions
