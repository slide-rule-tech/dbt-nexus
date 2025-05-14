{% macro nexus_finalize_participants(entity_type) %}

with resolved_identifiers as (
  select * from {{ ref('resolved_' ~ entity_type ~ '_identifiers') }}
),

entity_identifiers as (
  select
    *
  from {{ref(entity_type ~ '_identifiers')}}
),

joined as (
  select
    ri.{{ entity_type }}_id,
    ri.identifier_type,
    ri.identifier_value,
    ei.event_id
  from entity_identifiers ei
  inner join resolved_identifiers ri on ei.identifier_value = ri.identifier_value and ei.identifier_type = ri.identifier_type
)

-- Final output with just the unique entity_id and event_id combinations
select
  {{ dbt_utils.generate_surrogate_key(['event_id', entity_type ~ '_id']) }} as {{ entity_type }}_participant_id,
  event_id,
  {{ entity_type }}_id
from joined
group by event_id, {{ entity_type }}_id
{% endmacro %}