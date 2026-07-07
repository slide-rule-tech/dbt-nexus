{{ config(tags=["it_invariant"]) }}

-- Participants may never point at an entity id that lost a merge: the
-- repoint leg must move rows off repointed previous_entity_ids in the same
-- run that logged the repoint.
select
    p.entity_participant_id,
    p.entity_type,
    p.entity_id as dead_entity_id_still_referenced
from {{ ref('nexus_entity_participants') }} p
join (
    select distinct entity_type, previous_entity_id
    from {{ ref('nexus_resolution_log') }}
    where resolution_reason = 'repointed'
) losers
  on p.entity_type = losers.entity_type
 and p.entity_id = losers.previous_entity_id
