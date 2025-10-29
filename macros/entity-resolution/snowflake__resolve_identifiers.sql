{% macro snowflake__resolve_identifiers(entity_type, identifiers_table, edges_table, max_recursion=10) %}

with recursive recursive_components as (
    -- Base case : start from every identifier that appears in the raw table for this entity_type.
    select distinct
      identifier_type  as component_identifier_type,
      identifier_value as component_identifier_value,
      identifier_type,
      identifier_value,
      -- Keep track of the identifiers that have already been visited using a string path
      identifier_type || ':' || identifier_value as path,
      0 as recursion_level
    from {{ ref(identifiers_table) }}
    where entity_type = '{{ entity_type }}'

    union all

    -- Recursive case : walk to every neighbour that hasn't been visited yet.
    select
      rc.component_identifier_type,
      rc.component_identifier_value,
      e.identifier_type_b  as identifier_type,
      e.identifier_value_b as identifier_value,
      -- Append the new identifier to the path string
      rc.path || '|' || e.identifier_type_b || ':' || e.identifier_value_b as path,
      rc.recursion_level + 1 as recursion_level
    from recursive_components rc
    join {{ ref(edges_table) }} e
      on rc.identifier_type  = e.identifier_type_a
     and rc.identifier_value = e.identifier_value_a
     and e.entity_type_a = '{{ entity_type }}'
     and e.entity_type_b = '{{ entity_type }}'
    -- Use string operations to check for cycles
    where not contains(rc.path, e.identifier_type_b || ':' || e.identifier_value_b)
    and rc.recursion_level < {{ max_recursion }}
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