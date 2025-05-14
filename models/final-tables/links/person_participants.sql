{{ config(materialized='table', tags=['identity-resolution', 'persons', 'realtime']) }}

with resolved_identifiers as (
  select * from {{ ref('resolved_person_identifiers') }}
),

person_identifiers as (
  select
    *
  from {{ref('person_identifiers')}}
),

joined as (
  select
    ri.person_id,
    ri.identifier_value,
    ri.identifier_type,
    pi.event_id
  from person_identifiers pi
  inner join resolved_identifiers ri on pi.identifier_value = ri.identifier_value and pi.identifier_type = ri.identifier_type
)

-- Final output with just the unique person_id and event_id combinations
select
  {{ dbt_utils.generate_surrogate_key(['event_id', 'person_id']) }} as person_participant_id,
  event_id,
  person_id
from joined
group by event_id, person_id