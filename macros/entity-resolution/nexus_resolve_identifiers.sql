{% macro nexus_resolve_identifiers(entity_type, identifiers_table, edges_table) %}

with recursive recursive_components as (
    -- Base case : start from every identifier that appears in the raw table.
    select distinct
      identifier_type  as component_identifier_type,
      identifier_value as component_identifier_value,
      identifier_type,
      identifier_value,
      -- Keep track of the identifiers that have already been visited so we
      -- don't revisit them in later iterations.
      [struct(identifier_type as identifier_type,
              identifier_value as identifier_value)] as path
    from {{ ref(identifiers_table) }}

    union all

    -- Recursive case : walk to every neighbour that hasn't been visited yet.
    select
      rc.component_identifier_type,
      rc.component_identifier_value,
      e.identifier_type_b  as identifier_type,
      e.identifier_value_b as identifier_value,
      array_concat(
        rc.path,
        [struct(e.identifier_type_b  as identifier_type,
                 e.identifier_value_b as identifier_value)]
      )                                                   as path
    from recursive_components rc
    join {{ ref(edges_table) }} e
      on rc.identifier_type  = e.identifier_type_a
     and rc.identifier_value = e.identifier_value_a
    -- BigQuery allows only one reference to the recursive CTE in the
    -- recursive term.  To avoid a second reference we use the running `path`
    -- array to ensure we don't revisit identifiers that are already in the
    -- component, which would otherwise create cycles.
    where not exists (
      select 1
      from unnest(rc.path) p
      where p.identifier_type  = e.identifier_type_b
        and p.identifier_value = e.identifier_value_b
    )
),

-- Return the deduplicated component mapping (drop the helper `path` column).
deduplicated as (
  select distinct
    component_identifier_type,
    component_identifier_value,
    identifier_type,
    identifier_value
  from recursive_components
),
-- First apply window functions to get the first values 
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
  from deduplicated
),

-- Then use those pre-calculated values in the mapping
component_mapping as (
  select
    identifier_type,
    identifier_value,
    {{ dbt_utils.generate_surrogate_key([
      'first_component_type',
      'first_component_value'
    ]) }} as component_id
  from component_values
  group by identifier_type, identifier_value, first_component_type, first_component_value
),

entity_identifiers as (
  select * from {{ ref(identifiers_table) }}
),

resolved_identifiers as (
  select
    u.row_id,
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
    row_id,
    -- Use ROW_NUMBER to identify duplicates
    row_number() over(
      partition by identifier_type, identifier_value
      order by row_id  -- Keep the earliest occurrence by row_id
    ) as row_num
  from resolved_identifiers
)

--  Output the deduplicated records
select
  {{ dbt_utils.generate_surrogate_key([entity_type ~ '_id', 'identifier_type', 'identifier_value']) }} as identifier_id,
  {{ entity_type }}_id,
  event_id,
  identifier_type,
  identifier_value,
  false as realtime_processed,
  true as existing_{{ entity_type }}
from deduplicated_identifiers 
where row_num = 1 
{% endmacro %} 