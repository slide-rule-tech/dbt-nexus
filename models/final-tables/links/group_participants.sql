{{ config(materialized='table', tags=['identity-resolution', 'groups']) }}

with resolved_identifiers as (
  select * from {{ ref('resolved_group_identifiers') }}
),

group_identifiers as (
  select
    *
  from {{ref('group_identifiers')}}
),

joined as (
  select
    ri.group_id,
    ri.identifier_type,
    ri.identifier_value,
    gi.event_id
  from group_identifiers gi
  inner join resolved_identifiers ri on gi.identifier_value = ri.identifier_value and gi.identifier_type = ri.identifier_type
)

-- Final output with just the unique group_id and event_id combinations
select
  {{ dbt_utils.generate_surrogate_key(['event_id', 'group_id']) }} as group_participant_id,
  event_id,
  group_id
from joined
group by event_id, group_id