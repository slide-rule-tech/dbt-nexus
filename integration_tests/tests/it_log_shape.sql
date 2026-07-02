{{ config(tags=["it_invariant"]) }}

-- Structural invariants of the resolution log.
with log as (
    select * from {{ ref('nexus_resolution_log') }}
)

select 'reobserved row leaked into the log' as reason, resolution_id
from log where resolution_reason = 'reobserved'

union all

select 'repointed without a valid previous_entity_id', resolution_id
from log
where resolution_reason = 'repointed'
  and (previous_entity_id is null or previous_entity_id = entity_id)

union all

select 'non-repointed row carries previous_entity_id', resolution_id
from log
where resolution_reason in ('born', 'accreted', 'full_resolution')
  and previous_entity_id is not null

union all

select 'unknown resolution_reason: ' || resolution_reason, resolution_id
from log
where resolution_reason not in ('born', 'accreted', 'repointed', 'full_resolution')

union all

select 'entity id prefix does not match entity type', resolution_id
from log
where (entity_type = 'person' and substr(entity_id, 1, 4) != 'per_')
   or (entity_type = 'group' and substr(entity_id, 1, 4) != 'grp_')
