{{ config(materialized='view', tags=['compatibility']) }}

select
    entity_participant_id as group_participant_id,
    event_id,
    entity_id as group_id,
    role
from {{ ref('nexus_entity_participants') }}
where entity_type = 'group'
