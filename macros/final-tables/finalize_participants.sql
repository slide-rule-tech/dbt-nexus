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
-- One row per (event, entity, role) — the same three columns the id hashes.
--
-- The grouping deliberately excludes occurred_at. A single entity can reach one
-- event through several identifier rows, and those rows do not have to share a
-- timestamp: a source that models a thread or session as one event emits an
-- identifier row per message with that message's time. Grouping on occurred_at
-- as well would then emit one row per timestamp while the id still hashes only
-- (event_id, entity_id, role) — duplicate ids under a declared primary key.
--
-- min() gives the entity's first participation in the event, which matches the
-- event's own occurred_at whenever the source does put every identifier row at
-- the event time.
select
  {{ nexus.create_nexus_id('entity_participant', ['event_id', entity_type ~ '_id', 'role']) }} as entity_participant_id,
  '{{ entity_type }}' as entity_type,
  event_id,
  {{ entity_type }}_id as entity_id,
  role,
  min(occurred_at) as occurred_at
from joined
group by event_id, {{ entity_type }}_id, role
{% endmacro %}
