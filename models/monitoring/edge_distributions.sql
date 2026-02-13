{{ config(materialized='view', tags=['analysis', 'edge-quality', 'identity-resolution']) }}

{% set nexus_config = var('nexus', {}) %}
{% set edge_quality = nexus_config.get('edge_quality', {}) %}
{% set critical_threshold = edge_quality.get('critical_threshold', 50) %}
{% set error_threshold = edge_quality.get('error_threshold', 20) %}
{% set warning_threshold = edge_quality.get('warning_threshold', 10) %}

-- Edge Quality Distribution Analysis
-- Analyzes edge connections per identifier WITHOUT filtering to identify all problematic identifiers
-- This allows examining issues even when autofilters are enabled
-- Note: This shows ALL edges, not just filtered ones

-- Recreate edges WITHOUT filtering for analysis
with unpivoted as (
  select * from {{ ref('nexus_entity_identifiers') }}
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

all_edges as (
  select
    edge_id,
    entity_type_a,
    identifier_type_a,
    identifier_value_a,
    entity_type_b,
    identifier_type_b,
    identifier_value_b,
    source
  from deduplicated_edges
  where rn = 1
),

edge_distribution as (
    select
        e.entity_type_a,
        e.identifier_type_a,
        e.identifier_value_a,
        count(distinct e.identifier_value_b) as unique_connections,
        {% if target.type == 'bigquery' %}
        string_agg(distinct e.identifier_type_b, ', ' order by e.identifier_type_b) as connected_types
        {% elif target.type == 'snowflake' %}
        listagg(distinct e.identifier_type_b, ', ') within group (order by e.identifier_type_b) as connected_types
        {% else %}
        string_agg(distinct e.identifier_type_b, ', ' order by e.identifier_type_b) as connected_types
        {% endif %}
    from all_edges e
    group by e.entity_type_a, e.identifier_type_a, e.identifier_value_a
),

source_attribution as (
    select
        e.entity_type_a,
        e.identifier_type_a,
        e.identifier_value_a,
        e.source,
        count(*) as edge_count_from_source
    from all_edges e
    where e.source is not null
    group by e.entity_type_a, e.identifier_type_a, e.identifier_value_a, e.source
),

source_breakdown as (
    select
        entity_type_a,
        identifier_type_a,
        identifier_value_a,
        {% if target.type == 'bigquery' %}
        string_agg(source || ' (' || edge_count_from_source || ')', ', ' 
            order by edge_count_from_source desc) as source_distribution
        {% elif target.type == 'snowflake' %}
        listagg(source || ' (' || edge_count_from_source || ')', ', ') within group 
            (order by edge_count_from_source desc) as source_distribution
        {% else %}
        string_agg(source || ' (' || edge_count_from_source || ')', ', ' 
            order by edge_count_from_source desc) as source_distribution
        {% endif %}
    from source_attribution
    group by entity_type_a, identifier_type_a, identifier_value_a
)

select
    ed.*,
    coalesce(sb.source_distribution, 'unknown') as source_distribution,
    case
        when ed.unique_connections > {{ critical_threshold }} then 'CRITICAL'
        when ed.unique_connections > {{ error_threshold }} then 'ERROR'
        when ed.unique_connections > {{ warning_threshold }} then 'WARNING'
        else 'OK'
    end as severity
from edge_distribution ed
left join source_breakdown sb
    on ed.entity_type_a = sb.entity_type_a
    and ed.identifier_type_a = sb.identifier_type_a
    and ed.identifier_value_a = sb.identifier_value_a
where ed.unique_connections > {{ warning_threshold }}
order by ed.unique_connections desc

