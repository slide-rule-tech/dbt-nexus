{{ config(materialized='table') }}

-- Shadow resolution: the trusted full-resolution algorithm run from scratch
-- over everything visible at the current clock. The partition (which
-- identifiers group together) produced incrementally must equal this at
-- every step -- that is the load-bearing invariant of the whole design.
-- Entity ids are allowed to differ (labels are bookkeeping); the
-- partition-equality tests compare co-membership only.
{{ nexus.resolve_identifiers('person', 'it_visible_identifiers', 'it_shadow_edges', 10) }}
