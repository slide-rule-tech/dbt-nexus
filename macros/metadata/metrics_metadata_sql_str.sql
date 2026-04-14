{# Snowflake escapes single quotes as '', while BigQuery expects \'.
   Use adapter-aware escaping so metadata strings compile across warehouses. #}
{% macro metrics_metadata_sql_str(value) -%}
{%- set raw_value = (value | default("", true)) | string -%}
{%- if target.type == 'bigquery' -%}
    '{{ raw_value | replace("\\", "\\\\") | replace("'", "\\'") }}'
{%- else -%}
    '{{ raw_value | replace("'", "''") }}'
{%- endif -%}
{%- endmacro %}
