{# DuckDB implementation of resolve_identifiers.

    Identical Jinja-unrolled CTE shape to snowflake__resolve_identifiers —
    the SQL uses only standard window functions, UNION (dedup), and CTEs,
    all of which DuckDB supports with the same semantics as Snowflake.

    Without this, projects using dbt-nexus on a DuckDB target fail to
    parse with "No macro named 'resolve_identifiers' found within
    namespace: 'dbt_nexus'", since dispatch only knows about snowflake__
    and bigquery__ variants.
#}
{% macro duckdb__resolve_identifiers(entity_type, identifiers_table, edges_table, max_recursion=10) %}

with depth_0 as (
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

deduplicated_identifiers as (
  select
    identifier_type,
    identifier_value,
    {{ entity_type }}_id,
    event_id,
    edge_id,
    row_number() over(
      partition by identifier_type, identifier_value
      order by edge_id
    ) as row_num
  from resolved_identifiers
)

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
