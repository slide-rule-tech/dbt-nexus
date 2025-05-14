{{ config(materialized='view', tags=['realtime',  'persons']) }}

select distinct
    {{ dbt_utils.generate_surrogate_key(['event_id', 'person_id']) }} as person_participant_id,
    event_id, 
    person_id 
from {{ ref('realtime_resolved_person_identifiers') }} -- DIRECTIVE: inject alasql sql table=realtime_resolved_person_identifiers