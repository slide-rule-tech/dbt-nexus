{{ config(materialized='view', tags=['realtime', 'groups']) }}

select distinct
    {{ dbt_utils.generate_surrogate_key(['event_id', 'group_id']) }} as group_participant_id,
    event_id, 
    group_id 
from {{ ref('realtime_resolved_group_identifiers') }} -- DIRECTIVE: inject alasql sql table=realtime_resolved_group_identifiers