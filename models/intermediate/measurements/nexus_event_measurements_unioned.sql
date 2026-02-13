{{ config(materialized='table') }}

-- Nexus Event Measurements
-- Unions all source-level event measurement models into a single table.
-- Each row represents a single quantitative observation extracted from an event.

{{ nexus.process_event_measurements() }}
order by occurred_at desc
