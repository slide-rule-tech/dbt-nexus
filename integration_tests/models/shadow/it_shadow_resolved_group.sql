{{ config(materialized='table') }}

-- See it_shadow_resolved_person.sql.
{{ nexus.resolve_identifiers('group', 'it_visible_identifiers', 'it_shadow_edges', 10) }}
