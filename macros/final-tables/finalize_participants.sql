{% macro finalize_participants(entity_type) %}
with resolved_identifiers as (
  select * from {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }}
),
entity_identifiers as (
  select * from {{ ref('nexus_entity_identifiers') }}
  where entity_type = '{{ entity_type }}'
),
joined as (
  select
    ri.{{ entity_type }}_id,
    ri.identifier_type,
    ri.identifier_value,
    ei.event_id,
    ei.role,
    ei.occurred_at
  from entity_identifiers ei
  inner join resolved_identifiers ri
    on ei.identifier_value = ri.identifier_value
    and ei.identifier_type = ri.identifier_type
)
select
  {{ nexus.create_nexus_id('entity_participant', ['event_id', entity_type ~ '_id', 'role']) }} as entity_participant_id,
  '{{ entity_type }}' as entity_type,
  event_id,
  {{ entity_type }}_id as entity_id,
  role,
  occurred_at
from joined
group by event_id, {{ entity_type }}_id, role, occurred_at
{% endmacro %}
