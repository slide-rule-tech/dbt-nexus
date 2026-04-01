{# Snowflake string literals use single quotes; double quotes delimit identifiers, not strings.
   Escape any embedded single quote as '' so YAML filters like event_name = 'x' compile safely. #}
{% macro metrics_metadata_sql_str(value) -%}
'{{ (value | default("", true)) | string | replace("'", "''") }}'
{%- endmacro %}
