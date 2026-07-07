{{ config(tags=["it_invariant"]) }}

-- Internal consistency on the DISTINCT grain: participants must equal
-- exactly what the CURRENT resolved mapping implies from the identifier
-- rows — no missing rows (append leg lost something) and no extras
-- (repoint leg pointed somewhere the mapping doesn't). The distinct grain
-- deliberately tolerates the documented post-merge duplicate-id divergence.
with
{% for t in ['person', 'group'] %}
expected_{{ t }} as (
    select distinct ei.event_id, m.{{ t }}_id as entity_id, ei.role
    from {{ ref('nexus_entity_identifiers') }} ei
    join {{ ref('nexus_resolved_' ~ t ~ '_identifiers') }} m
      on ei.identifier_type = m.identifier_type
     and ei.identifier_value = m.identifier_value
    where ei.entity_type = '{{ t }}'
),
actual_{{ t }} as (
    select distinct event_id, entity_id, role
    from {{ ref('nexus_entity_participants') }}
    where entity_type = '{{ t }}'
){{ "," if not loop.last }}
{% endfor %}

{% for t in ['person', 'group'] %}
select '{{ t }}' as entity_type, 'missing' as problem, e.event_id, e.entity_id, e.role
from expected_{{ t }} e
left join actual_{{ t }} a
  on e.event_id = a.event_id and e.entity_id = a.entity_id and e.role is not distinct from a.role
where a.event_id is null
union all
select '{{ t }}' as entity_type, 'extra' as problem, a.event_id, a.entity_id, a.role
from actual_{{ t }} a
left join expected_{{ t }} e
  on e.event_id = a.event_id and e.entity_id = a.entity_id and e.role is not distinct from a.role
where e.event_id is null
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
