{{ config(tags=["it_invariant"]) }}

-- No identifier may map to an entity id that lost a merge: repointed
-- previous_entity_ids are dead forever (within an epoch -- the harness runs
-- one epoch per scenario database).
{% for t in ['person', 'group'] %}
select
    '{{ t }}' as entity_type,
    m.identifier_type,
    m.identifier_value,
    m.{{ t }}_id as dead_entity_id_still_live
from {{ ref('nexus_resolved_' ~ t ~ '_identifiers') }} m
join (
    select distinct previous_entity_id
    from {{ ref('nexus_resolution_log') }}
    where resolution_reason = 'repointed'
      and entity_type = '{{ t }}'
) losers on m.{{ t }}_id = losers.previous_entity_id
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
