{{ config(materialized='table', tags=['identity-resolution', 'participants', 'realtime']) }}

{% set entity_types = var('nexus', {}).get('entity_types', []) %}

with 
{% for entity_type in entity_types %}
{{ entity_type }}_participants as (
  {{ nexus.finalize_participants(entity_type) }}
){{ "," if not loop.last }}
{% endfor %}

{% for entity_type in entity_types %}
{% if loop.first %}
select * from {{ entity_type }}_participants
{% else %}
union all
select * from {{ entity_type }}_participants
{% endif %}
{% endfor %}
