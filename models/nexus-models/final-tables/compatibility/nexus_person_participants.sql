{{ config(materialized='view', tags=['compatibility']) }}

select
    entity_participant_id as person_participant_id,
    event_id,
    entity_id as person_id,
    role
from {{ ref('nexus_entity_participants') }}
where entity_type = 'person'
