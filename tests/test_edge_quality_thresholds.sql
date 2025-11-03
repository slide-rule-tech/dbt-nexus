-- Edge Quality Threshold Test
-- Fails if any identifier in the FILTERED edges has more connections than the error threshold
-- This validates that autofilters are working correctly and prevents builds from proceeding
-- if filtered edges still exceed the error threshold

{% set nexus_config = var('nexus', {}) %}
{% set edge_quality = nexus_config.get('edge_quality', {}) %}
{% set error_threshold = edge_quality.get('error_threshold', 20) %}

-- Read directly from filtered nexus_entity_identifiers_edges to validate filtered results
with edge_distribution as (
    select
        e.entity_type_a,
        e.identifier_type_a,
        e.identifier_value_a,
        count(distinct e.identifier_value_b) as unique_connections
    from {{ ref('nexus_entity_identifiers_edges') }} e
    group by e.entity_type_a, e.identifier_type_a, e.identifier_value_a
)

select
    entity_type_a,
    identifier_type_a,
    identifier_value_a,
    unique_connections
from edge_distribution
where unique_connections > {{ error_threshold }}
