{# Cross-adapter wrapper for casting an HH:MM:SS-style duration string
   into an INTERVAL type.

   Snowflake: `cast(s as interval hour(9) to second(0))` — with precision
              spec required for sub-second / over-24-hour durations.
   DuckDB:    `cast(s as interval)` — no precision spec; auto-parses
              HH:MM:SS and similar forms.

   Snowflake also has try_cast(s as interval ...). Match that with a
   `try` flag.
#}
{% macro interval_cast(column, try=false) %}
{%- if target.type == 'duckdb' -%}
  {%- if try -%}try_cast({{ column }} as interval)
  {%- else -%}cast({{ column }} as interval)
  {%- endif -%}
{%- else -%}
  {%- if try -%}try_cast({{ column }} as interval hour(9) to second(0))
  {%- else -%}cast({{ column }} as interval hour(9) to second(0))
  {%- endif -%}
{%- endif -%}
{% endmacro %}
