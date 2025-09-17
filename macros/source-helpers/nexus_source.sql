{% macro nexus_source(source_name, table_name=none) %}
  {%- set source_config = var('nexus', {}).get(source_name, {}) -%}
  {%- set location = source_config.get('location', {}) -%}
  
  {%- set schema_name = location.get('schema', source_name) -%}
  {%- set table_name = table_name or location.get('table', 'events') -%}
  
  {{ source(schema_name, table_name) }}
{% endmacro %}
