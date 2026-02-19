{{ config(materialized='table') }}

-- Nexus Event Dimensions
-- Unions all source-level event dimension models into a single table.
-- Each row represents a single categorical property extracted from an event.

{{ nexus.process_event_dimensions() }}
order by occurred_at desc
