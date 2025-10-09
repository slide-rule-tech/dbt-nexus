{% macro finalize_entities() %}

with resolved_traits as (
  select * from {{ ref('nexus_resolved_entity_traits') }}
),

-- Get all distinct entity IDs from all entity types
all_entities as (
    {% set entity_types = var('nexus_entity_types', ['person', 'group']) %}
    {% for entity_type in entity_types %}
        select
            {{ entity_type }}_id as entity_id,
            '{{ entity_type }}' as entity_type
        from {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }}
        {% if not loop.last %}
        union all
        {% endif %}
    {% endfor %}
),

distinct_entities as (
  select distinct
    entity_id,
    entity_type
  from all_entities
),

-- Pivot traits
pivoted_traits as (
  {{ nexus.pivot_traits('nexus_resolved_entity_traits', 'entity_id', 'traits_') }}
)

-- Join distinct entity IDs with traits
select
  e.entity_id,
  e.entity_type,
  t.*
from distinct_entities e
left join pivoted_traits t on e.entity_id = t.traits_entity_id
{% endmacro %} 