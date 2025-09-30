{% macro nexus_source(source_name, table_name=none) %}
  {%- set source_config = var('nexus', {}).get(source_name, {}) -%}
  {%- set location = source_config.get('location', {}) -%}
  
  {%- set schema_name = location.get('schema', source_name) -%}
  {%- if table_name -%}
    {%- set actual_table_name = location.get('tables', {}).get(table_name, table_name) -%}
  {%- else -%}
    {%- set actual_table_name = location.get('table', 'events') -%}
  {%- endif -%}
  
  {{ source(schema_name, actual_table_name) }}
{% endmacro %}
