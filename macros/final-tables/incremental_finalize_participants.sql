{#
  Incremental legs for nexus_entity_participants (used when
  nexus.incremental.enabled; the full-resolution path keeps using
  finalize_participants / finalize_non_er_participants unchanged).

  Semantics mirror stable entity ids: entity_participant_id is minted at
  birth from (event_id, entity_id, role) and NEVER rewritten — merges update
  entity_id in place via the repoint leg. Accepted divergence vs a full
  rebuild: after a merge, the same (event_id, entity_type, entity_id, role)
  grain can carry two rows (the loser's repointed row plus the survivor's
  own). Ids stay unique; parity checks compare on the DISTINCT grain.
#}

{# Append leg (ER types): new-event participant rows, watermark on the
   entity-identifiers ingestion clock. #}
{% macro incremental_finalize_participants(entity_type) %}
with resolved_identifiers as (
  select * from {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }}
),
entity_identifiers as (
  select * from {{ ref('nexus_entity_identifiers') }}
  where entity_type = '{{ entity_type }}'
  {% if is_incremental() %}
    and _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
  {% endif %}
),
joined as (
  select
    ri.{{ entity_type }}_id,
    ei.event_id,
    ei.role,
    ei.occurred_at,
    ei._ingested_at
  from entity_identifiers ei
  inner join resolved_identifiers ri
    on ei.identifier_value = ri.identifier_value
    and ei.identifier_type = ri.identifier_type
),
grouped as (
  select
    {{ nexus.create_nexus_id('entity_participant', ['event_id', entity_type ~ '_id', 'role']) }} as entity_participant_id,
    '{{ entity_type }}' as entity_type,
    event_id,
    {{ entity_type }}_id as entity_id,
    role,
    occurred_at,
    max(_ingested_at) as _ingested_at
  from joined
  group by event_id, {{ entity_type }}_id, role, occurred_at
)
select g.*
from grouped g
{% if is_incremental() %}
{# Re-sync-after-merge guard: a re-offered identifier row resolves to the
   post-merge survivor, minting a NEW id for a grain that may already exist
   under the pre-merge id. Skip those; same-id rows still merge through. #}
left join {{ this }} t
  on t.event_id = g.event_id
  and t.entity_type = g.entity_type
  and t.entity_id = g.entity_id
  and t.role is not distinct from g.role
  and t.entity_participant_id != g.entity_participant_id
where t.entity_participant_id is null
{% endif %}
{% endmacro %}


{# Append leg (non-ER types): registration-model join, same clock. #}
{% macro incremental_finalize_non_er_participants(entity_type) %}
{% set entity_config = nexus.get_entity_type_config() %}
{% set type_config = entity_config[entity_type] %}
{% set reg_model = type_config.get('registration_model') %}

{% if reg_model %}
with entity_identifiers as (
  select * from {{ ref('nexus_entity_identifiers') }}
  where entity_type = '{{ entity_type }}'
  {% if is_incremental() %}
    and _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
  {% endif %}
),
registered_entities as (
  select entity_id, source_id
  from {{ ref(reg_model) }}
),
joined as (
  select
    reg.entity_id,
    ei.event_id,
    ei.role,
    ei.occurred_at,
    ei._ingested_at
  from entity_identifiers ei
  inner join registered_entities reg
    on ei.identifier_value = reg.source_id
)
select
  {{ nexus.create_nexus_id('entity_participant', ['event_id', 'entity_id', 'role']) }} as entity_participant_id,
  '{{ entity_type }}' as entity_type,
  event_id,
  entity_id,
  role,
  occurred_at,
  max(_ingested_at) as _ingested_at
from joined
group by event_id, entity_id, role, occurred_at
{% else %}
select
  cast(null as {{ dbt.type_string() }}) as entity_participant_id,
  cast(null as {{ dbt.type_string() }}) as entity_type,
  cast(null as {{ dbt.type_string() }}) as event_id,
  cast(null as {{ dbt.type_string() }}) as entity_id,
  cast(null as {{ dbt.type_string() }}) as role,
  cast(null as {{ dbt.type_timestamp() }}) as occurred_at,
  cast(null as {{ dbt.type_timestamp() }}) as _ingested_at
from (select 1) _ where 1=0
{% endif %}
{% endmacro %}


{# Repoint leg (ER types, incremental runs only): rows sitting at a merged-
   away entity move to the survivor. Joining log rows to the CURRENT resolved
   table (not to rl.entity_id) makes the mapping self-healing across batches:
   an unconsumed A→B followed by B→C resolves A directly to C — no
   transitive-closure pass needed. The id is untouched. #}
{% macro incremental_participants_repoint(entity_type) %}
select
  t.entity_participant_id,
  t.entity_type,
  t.event_id,
  m.new_entity_id as entity_id,
  t.role,
  t.occurred_at,
  t._ingested_at
from {{ this }} t
inner join (
  select distinct rl.previous_entity_id, cur.{{ entity_type }}_id as new_entity_id
  from {{ ref('nexus_resolution_log') }} rl
  inner join {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }} cur
    on cur.identifier_type = rl.identifier_type
    and cur.identifier_value = rl.identifier_value
  where rl.entity_type = '{{ entity_type }}'
    and rl.resolution_reason = 'repointed'
    and rl.resolved_at_watermark > {{ nexus.nexus_incremental_watermark_literal('_resolution_log_watermark') }}
) m
  on t.entity_id = m.previous_entity_id
where t.entity_type = '{{ entity_type }}'
{% endmacro %}
