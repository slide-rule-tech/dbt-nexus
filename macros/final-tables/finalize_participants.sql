{% macro finalize_participants(entity_type) %}

with resolved_identifiers as (
  select * from {{ ref('nexus_resolved_entity_identifiers') }}
  where entity_type = '{{ entity_type }}'
),

entity_identifiers as (
  select
    *
  from {{ref('nexus_entity_identifiers')}}
  where entity_type = '{{ entity_type }}'
),

joined as (
  select
    ri.entity_id,
    ri.identifier_type,
    ri.identifier_value,
    ei.event_id,
    ei.role
  from entity_identifiers ei
  inner join resolved_identifiers ri on ei.identifier_value = ri.identifier_value and ei.identifier_type = ri.identifier_type
)

-- Final output with just the unique entity_id and event_id combinations
select
  {{ create_nexus_id('entity_participant', ['event_id', 'entity_id', 'role']) }} as entity_participant_id,
  event_id,
  entity_id,
  '{{ entity_type }}' as entity_type,
  role
from joined
group by event_id, entity_id, role
{% endmacro %}