{% macro create_identifier_edges(identifiers_table) %}

with unpivoted as (
  select * from {{ ref(identifiers_table) }}
)

-- Define the edges between identifiers
select
  a.identifier_type as identifier_type_a,
  a.identifier_value as identifier_value_a,
  b.identifier_type as identifier_type_b,
  b.identifier_value as identifier_value_b
from unpivoted a
join unpivoted b
  on a.row_id = b.row_id
  and (a.identifier_type != b.identifier_type or a.identifier_value != b.identifier_value)

{% endmacro %}
