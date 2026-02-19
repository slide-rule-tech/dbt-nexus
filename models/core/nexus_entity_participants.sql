{{ config(materialized='table', tags=['identity-resolution', 'participants', 'realtime']) }}

{% set er_types = nexus.get_er_entity_types() %}
{% set non_er_types = nexus.get_non_er_entity_types() %}
{% set entity_config = nexus.get_entity_type_config() %}

with
{% for entity_type in er_types %}
{{ entity_type }}_participants as (
  {{ nexus.finalize_participants(entity_type) }}
){{ "," if not loop.last or non_er_types | length > 0 }}
{% endfor %}

{% for entity_type in non_er_types %}
{{ entity_type }}_participants as (
  {{ nexus.finalize_non_er_participants(entity_type) }}
){{ "," if not loop.last }}
{% endfor %}

{% set all_types = er_types + non_er_types %}
{% for entity_type in all_types %}
{% if loop.first %}
select * from {{ entity_type }}_participants
{% else %}
union all
select * from {{ entity_type }}_participants
{% endif %}
{% endfor %}
