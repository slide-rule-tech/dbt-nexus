{% macro finalize_entity(entity_type) %}

with resolved_traits as (
  select * from {{ ref('nexus_resolved_entity_traits') }}
  where entity_type = '{{ entity_type }}'
),

-- Get distinct entity IDs first
distinct_entities as (
  select
    distinct entity_id
  from {{ ref('nexus_resolved_entity_identifiers') }}
  where entity_type = '{{ entity_type }}'
),

-- Then pivot traits separately
pivoted_traits as (
  {{ pivot_traits('nexus_resolved_entity_traits', 'entity_id', 'traits_', "entity_type = '" ~ entity_type ~ "'") }}
)

-- Join distinct IDs with traits
select
  e.entity_id,
  '{{ entity_type }}' as entity_type,
  t.*
from distinct_entities e
left join pivoted_traits t on e.entity_id = t.traits_entity_id
{% endmacro %} 