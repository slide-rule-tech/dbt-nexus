{{ config(materialized='table', tags=['identity-resolution']) }}

{% set entity_types = var('nexus_entity_types', ['person', 'group']) %}

{% for entity_type in entity_types %}
  {% if not loop.first %}UNION ALL{% endif %}
  {{ create_identifier_edges('nexus_entity_identifiers', entity_type) }}
{% endfor %} 