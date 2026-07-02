{{ config(materialized='table') }}

-- Shadow edges: the same edge derivation the package uses, but rebuilt from
-- scratch over the full clock-visible slice every run (this model is a
-- table, so is_incremental() is false inside the macro and no watermark
-- filtering happens).
{{ nexus.create_identifier_edges('it_visible_identifiers') }}
