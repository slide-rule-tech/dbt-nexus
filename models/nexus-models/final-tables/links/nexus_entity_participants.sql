{{ config(materialized='table', tags=['identity-resolution', 'realtime']) }}

{% set entity_types = var('nexus_entity_types', ['person', 'group']) %}

{% for entity_type in entity_types %}
  {% if not loop.first %}UNION ALL{% endif %}
  {{ finalize_participants(entity_type) }}
{% endfor %} 