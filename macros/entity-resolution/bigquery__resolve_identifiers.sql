{% macro bigquery__resolve_identifiers(entity_type, identifiers_table, edges_table, max_recursion=10) %}

-- Jinja-unrolled traversal.
--
-- Compute depth-bounded reachability over the identifier graph by unrolling
-- the traversal at compile time. Because `max_recursion` is known to Jinja,
-- we render one CTE per hop instead of using SQL's `WITH RECURSIVE` primitive.
-- `UNION DISTINCT` at each level deduplicates `(component, reachable)` pairs,
-- which naturally absorbs cycles -- no path tracking (no array-of-struct)
-- required.
--
-- Output is identical to the prior recursive-CTE implementation for the same
-- inputs and `max_recursion`. Avoids BigQuery's structural restrictions on
-- `WITH RECURSIVE` (must be top-level of `WITH`, no UNION ALL with
-- non-recursive CTEs, no upstream-CTE references in the recursive body).

with
-- See snowflake__resolve_identifiers for the rationale on filtered-orphan
-- exclusion. Same logic applied here for BigQuery parity.
identifiers_with_surviving_edges as (
    select distinct entity_type_a as entity_type, identifier_type_a as identifier_type, identifier_value_a as identifier_value
    from {{ ref(edges_table) }}
    union distinct
    select distinct entity_type_b as entity_type, identifier_type_b as identifier_type, identifier_value_b as identifier_value
    from {{ ref(edges_table) }}
),

events_with_survivors as (
    select distinct ei.edge_id
    from {{ ref(identifiers_table) }} ei
    inner join identifiers_with_surviving_edges s
      on s.entity_type = ei.entity_type
      and s.identifier_type = ei.identifier_type
      and s.identifier_value = ei.identifier_value
    where ei.entity_type = '{{ entity_type }}'
),

filtered_orphan_identifiers as (
    -- Identifiers with no surviving edges that co-occurred in some event with
    -- another identifier that DID survive the noise filter. Excluded from
    -- depth_0 to avoid spurious singleton entities.
    select distinct ei.identifier_type, ei.identifier_value
    from {{ ref(identifiers_table) }} ei
    inner join events_with_survivors ews
      on ei.edge_id = ews.edge_id
    left join identifiers_with_surviving_edges s
      on s.entity_type = ei.entity_type
      and s.identifier_type = ei.identifier_type
      and s.identifier_value = ei.identifier_value
    where ei.entity_type = '{{ entity_type }}'
      and s.identifier_value is null
),

depth_0 as (
    -- Base case: every identifier starts as its own component.
    -- Excludes filtered orphans (see above).
    select distinct
      identifier_type  as component_identifier_type,
      identifier_value as component_identifier_value,
      identifier_type,
      identifier_value
    from {{ ref(identifiers_table) }} ei
    where entity_type = '{{ entity_type }}'
      and not exists (
        select 1 from filtered_orphan_identifiers fo
        where fo.identifier_type = ei.identifier_type
          and fo.identifier_value = ei.identifier_value
      )
)
{% for level in range(1, max_recursion + 1) %}
,
depth_{{ level }} as (
    -- Hop {{ level }}: extend reachability one more edge from depth_{{ level - 1 }}.
    select * from depth_{{ level - 1 }}
    union distinct
    select
      d.component_identifier_type,
      d.component_identifier_value,
      e.identifier_type_b  as identifier_type,
      e.identifier_value_b as identifier_value
    from depth_{{ level - 1 }} d
    join {{ ref(edges_table) }} e
      on d.identifier_type  = e.identifier_type_a
     and d.identifier_value = e.identifier_value_a
     and e.entity_type_a = '{{ entity_type }}'
     and e.entity_type_b = '{{ entity_type }}'
)
{% endfor %}
,

-- Apply window functions to pick the canonical component representative.
component_values as (
  select
    identifier_type,
    identifier_value,
    first_value(component_identifier_type) over(
      partition by identifier_type, identifier_value
      order by component_identifier_type, component_identifier_value
    ) as first_component_type,
    first_value(component_identifier_value) over(
      partition by identifier_type, identifier_value
      order by component_identifier_type, component_identifier_value
    ) as first_component_value
  from depth_{{ max_recursion }}
),

-- Then use those pre-calculated values in the mapping
component_mapping as (
  select
    identifier_type,
    identifier_value,
    {{ create_nexus_id(entity_type, ['first_component_type', 'first_component_value']) }} as component_id
  from component_values
  group by identifier_type, identifier_value, first_component_type, first_component_value
),

entity_identifiers as (
  select * from {{ ref(identifiers_table) }}
  where entity_type = '{{ entity_type }}'
),

resolved_identifiers as (
  select
    u.edge_id,
    u.event_id,
    u.identifier_type,
    u.identifier_value,
    c.component_id as {{ entity_type }}_id
  from entity_identifiers u
  join component_mapping c
    on u.identifier_type = c.identifier_type
    and u.identifier_value = c.identifier_value
),

-- Deduplicate identifiers to keep only one record per identifier value
deduplicated_identifiers as (
  select
    identifier_type,
    identifier_value,
    {{ entity_type }}_id,
    event_id,
    edge_id,
    -- Use ROW_NUMBER to identify duplicates
    row_number() over(
      partition by identifier_type, identifier_value
      order by edge_id  -- Keep the earliest occurrence by edge_id
    ) as row_num
  from resolved_identifiers
)

--  Output the deduplicated records
select
  {{ create_nexus_id(entity_type ~ '_identifier', [entity_type ~ '_id', 'identifier_type', 'identifier_value']) }} as {{ entity_type }}_identifier_id,
  {{ entity_type }}_id,
  event_id,
  identifier_type,
  identifier_value,
  false as realtime_processed,
  true as existing_{{ entity_type }},
  -- Resolution provenance (see incremental_resolve_identifiers): a full
  -- resolution is its own epoch. The watermark is the global ingestion
  -- high-water mark at resolution time so a subsequent incremental run
  -- picks up exactly where this one left off.
  'full_resolution' as resolution_reason,
  cast(null as {{ dbt.type_string() }}) as previous_entity_id,
  (
    select max(_ingested_at)
    from {{ ref(identifiers_table) }}
    where entity_type = '{{ entity_type }}'
  ) as resolved_at_watermark
from deduplicated_identifiers
where row_num = 1
{% endmacro %}
