{{ config(materialized='view') }}

-- The clock-visible identifier universe, shared by the shadow resolution.
-- Deliberately the same rows the incremental pipeline ingests (the shim),
-- so shadow-vs-incremental comparisons are apples to apples.
select * from {{ ref('it_entity_identifiers') }}
