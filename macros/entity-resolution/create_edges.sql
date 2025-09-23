{% macro create_identifier_edges(identifiers_table) %}

with unpivoted as (
  select * from {{ ref(identifiers_table) }}
),

raw_edges as (
  select
    a.edge_id,
    a.identifier_type as identifier_type_a,
    a.identifier_value as identifier_value_a,
    b.identifier_type as identifier_type_b,
    b.identifier_value as identifier_value_b,
    -- Create uniqueness hash for deduplication
    {{ dbt_utils.generate_surrogate_key([
      'a.identifier_type', 
      'a.identifier_value',
      'b.identifier_type', 
      'b.identifier_value'
    ]) }} as edge_uniqueness_hash
  from unpivoted a
  join unpivoted b
    on a.edge_id = b.edge_id
    and (a.identifier_type != b.identifier_type or a.identifier_value != b.identifier_value)
),

deduplicated_edges as (
  select
    edge_id,
    identifier_type_a,
    identifier_value_a,
    identifier_type_b,
    identifier_value_b,
    edge_uniqueness_hash,
    row_number() over (partition by edge_uniqueness_hash order by edge_uniqueness_hash) as rn
  from raw_edges
)

select
  edge_id,
  identifier_type_a,
  identifier_value_a,
  identifier_type_b,
  identifier_value_b
from deduplicated_edges
where rn = 1

{% endmacro %}
