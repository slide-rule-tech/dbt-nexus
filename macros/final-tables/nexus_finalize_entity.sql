{% macro nexus_finalize_entity(entity_type) %}

with resolved_traits as (
  select * from {{ ref('resolved_' ~ entity_type ~ '_traits') }}
),

-- Get distinct entity IDs first
distinct_entities as (
  select
    distinct {{ entity_type }}_id
  from {{ ref('resolved_' ~ entity_type ~ '_identifiers') }}
),

-- Then pivot traits separately
pivoted_traits as (
  {{ pivot_traits('resolved_' ~ entity_type ~ '_traits', entity_type ~ '_id', 'traits_') }}
)

-- Join distinct IDs with traits
select
  e.{{ entity_type }}_id,
  t.*
from distinct_entities e
left join pivoted_traits t on e.{{ entity_type }}_id = t.traits_{{ entity_type }}_id
{% endmacro %} 