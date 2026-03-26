{{ config(materialized='table', tags=['computed-traits', 'entities']) }}

-- Nexus Computed Traits
-- Unions all computed trait models into a single table.
-- Each row is a post-resolution entity property (risk scores, derived names,
-- external dataset merges) keyed directly by entity_id.

{{ nexus.process_computed_traits() }}
