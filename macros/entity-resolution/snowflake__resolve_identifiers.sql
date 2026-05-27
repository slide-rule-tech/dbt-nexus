{% macro snowflake__resolve_identifiers(entity_type, identifiers_table, edges_table, max_recursion=10) %}

-- Jinja-unrolled traversal.
--
-- Compute depth-bounded reachability over the identifier graph by unrolling
-- the traversal at compile time. Because `max_recursion` is known to Jinja,
-- we render one CTE per hop instead of using SQL's `WITH RECURSIVE` primitive.
-- `UNION` (not UNION ALL) at each level deduplicates `(component, reachable)`
-- pairs, which naturally absorbs cycles -- no path tracking required.
--
-- Output is identical to the prior recursive-CTE implementation for the same
-- inputs and `max_recursion`. Avoids Snowflake's recursive-operator memory
-- limits (error 100298) and BigQuery's structural restrictions on
-- `WITH RECURSIVE` (must be top-level, no UNION ALL with non-recursive CTEs).

with
-- Identifiers that co-occurred with other identifiers in some event but had
-- ALL their potential edges dropped by create_identifier_edges' noise filter
-- (e.g., a phone shared across hundreds of submissions). Without this step
-- each such identifier would survive depth_0 as its own singleton component
-- and turn into a standalone entity -- so a single event whose identifiers
-- include any of these orphans would resolve to multiple entities, one per
-- orphan, even though intra-event identifiers belong to one entity by
-- definition. We drop them from the base set; the non-orphan identifiers in
-- the same event still merge normally via their surviving edges.
identifiers_with_surviving_edges as (
    -- Identifiers that retained at least one edge after the noise filter,
    -- in either direction.
    select distinct entity_type_a as entity_type, identifier_type_a as identifier_type, identifier_value_a as identifier_value
    from {{ ref(edges_table) }}
    union
    select distinct entity_type_b as entity_type, identifier_type_b as identifier_type, identifier_value_b as identifier_value
    from {{ ref(edges_table) }}
),

events_with_survivors as (
    -- edge_ids (events) containing at least one identifier that has surviving
    -- edges. An identifier dropped to a singleton inside such an event is
    -- almost certainly a noise-filter casualty rather than a legitimate
    -- isolated participant.
    select distinct ei.edge_id
    from {{ ref(identifiers_table) }} ei
    inner join identifiers_with_surviving_edges s
      on s.entity_type = ei.entity_type
      and s.identifier_type = ei.identifier_type
      and s.identifier_value = ei.identifier_value
    where ei.entity_type = '{{ entity_type }}'
),

filtered_orphan_identifiers as (
    -- "Filtered orphans": identifiers with no surviving edges that co-occurred
    -- in some event with another identifier that DID survive. Without this
    -- exclusion they would each become their own singleton component and
    -- emit a spurious entity per event they appear in -- so a single event
    -- whose identifiers include any of these orphans would resolve to
    -- multiple entities, one per orphan, even though intra-event identifiers
    -- belong to one entity by definition. The non-orphan identifiers in the
    -- same event still merge normally via their surviving edges.
    --
    -- Note the "another survived in the same event" condition: a truly
    -- isolated single-identifier event (no co-occurring survivors) keeps its
    -- sole identifier as a legitimate singleton entity.
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
    -- Excludes filtered orphans (see above) so they don't surface as
    -- their own standalone entities.
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
    union
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
