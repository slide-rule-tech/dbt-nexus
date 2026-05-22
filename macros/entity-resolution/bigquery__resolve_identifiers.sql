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

with depth_0 as (
    -- Base case: every identifier starts as its own component.
    select distinct
      identifier_type  as component_identifier_type,
      identifier_value as component_identifier_value,
      identifier_type,
      identifier_value
    from {{ ref(identifiers_table) }}
    where entity_type = '{{ entity_type }}'
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
  true as existing_{{ entity_type }}
from deduplicated_identifiers
where row_num = 1
{% endmacro %}
