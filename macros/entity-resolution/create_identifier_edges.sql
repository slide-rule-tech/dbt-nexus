{% macro create_identifier_edges(identifiers_table) %}

{% set nexus_config = var('nexus', {}) %}
{% set edge_quality = nexus_config.get('edge_quality', {}) %}
{% set critical_autofilter = edge_quality.get('critical_autofilter', false) %}
{% set critical_threshold = edge_quality.get('critical_threshold', 50) %}
{% set error_autofilter = edge_quality.get('error_autofilter', false) %}
{% set error_threshold = edge_quality.get('error_threshold', 20) %}

with unpivoted as (
  select * from {{ ref(identifiers_table) }}
),

raw_edges as (
  select
    a.edge_id,
    a.entity_type as entity_type_a,
    a.identifier_type as identifier_type_a,
    a.identifier_value as identifier_value_a,
    b.entity_type as entity_type_b,
    b.identifier_type as identifier_type_b,
    b.identifier_value as identifier_value_b,
    -- Both a and b share the same edge_id, so they have the same source
    coalesce(a.source, b.source) as source,
    -- Create uniqueness hash for deduplication (includes entity_type to prevent collisions)
    {{ dbt_utils.generate_surrogate_key([
      'a.entity_type',
      'a.identifier_type', 
      'a.identifier_value',
      'b.entity_type',
      'b.identifier_type', 
      'b.identifier_value'
    ]) }} as edge_uniqueness_hash
  from unpivoted a
  join unpivoted b
    on a.edge_id = b.edge_id
    and (a.entity_type != b.entity_type 
         or a.identifier_type != b.identifier_type 
         or a.identifier_value != b.identifier_value)
),

deduplicated_edges as (
  select
    edge_id,
    entity_type_a,
    identifier_type_a,
    identifier_value_a,
    entity_type_b,
    identifier_type_b,
    identifier_value_b,
    source,
    edge_uniqueness_hash,
    row_number() over (partition by edge_uniqueness_hash order by edge_uniqueness_hash) as rn
  from raw_edges
),

edges_with_connection_counts as (
  select
    de.*,
    -- Count connections for identifier_a (how many different identifier_value_b it connects to)
    count(distinct de.identifier_value_b) over (
      partition by de.source, de.entity_type_a, de.identifier_type_a, de.identifier_value_a
    ) as connections_a_per_source,
    -- Count connections for identifier_b (how many different identifier_value_a it connects to)
    count(distinct de.identifier_value_a) over (
      partition by de.source, de.entity_type_b, de.identifier_type_b, de.identifier_value_b
    ) as connections_b_per_source
  from deduplicated_edges de
  where de.rn = 1
),

edges_with_total_connection_counts as (
  select
    ewc.*,
    -- Total connections for identifier_a across all sources
    count(distinct ewc.identifier_value_b) over (
      partition by ewc.entity_type_a, ewc.identifier_type_a, ewc.identifier_value_a
    ) as connections_a_total,
    -- Total connections for identifier_b across all sources
    count(distinct ewc.identifier_value_a) over (
      partition by ewc.entity_type_b, ewc.identifier_type_b, ewc.identifier_value_b
    ) as connections_b_total
  from edges_with_connection_counts ewc
)

select
  edge_id,
  entity_type_a,
  identifier_type_a,
  identifier_value_a,
  entity_type_b,
  identifier_type_b,
  identifier_value_b,
  source
from edges_with_total_connection_counts
where 
  -- Filter out identifiers with connections exceeding thresholds (if enabled)
  {% if critical_autofilter or error_autofilter %}
  not (
    {% if critical_autofilter %}
    (connections_a_total > {{ critical_threshold }} or connections_b_total > {{ critical_threshold }})
    {% if error_autofilter %} or {% endif %}
    {% endif %}
    {% if error_autofilter %}
    (connections_a_total > {{ error_threshold }} or connections_b_total > {{ error_threshold }})
    {% endif %}
  )
  {% else %}
  -- Connection filtering disabled
  1=1
  {% endif %}

{% endmacro %}
