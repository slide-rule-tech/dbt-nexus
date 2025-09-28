{{ config(
    materialized='table', 
    tags=['identity-resolution'],
) }}

{% set entity_types = var('nexus_entity_types', ['person', 'group']) %}

{% for entity_type in entity_types %}
  {% if not loop.first %}UNION ALL{% endif %}
  {{ resolve_identifiers(entity_type, 'nexus_entity_identifiers', 'nexus_entity_identifiers_edges', var('nexus_max_recursion', 10)) }}
{% endfor %}