{# Cross-adapter wrapper for the timezone conversion sprinkled
   throughout cinch's models. Snowflake's `convert_timezone(...)` has
   no DuckDB equivalent function — DuckDB uses the SQL-standard
   `AT TIME ZONE 'x' AT TIME ZONE 'y'` form. This macro renders the
   right SQL for the active target so the model SQL stays portable.

   Accepts both Snowflake signatures:

   - 2-arg: nexus_convert_timezone('UTC', col) — interpret col in the
     session/server timezone and convert to target_tz.
   - 3-arg: nexus_convert_timezone('America/New_York', 'UTC', col) —
     interpret col in source_tz and convert to target_tz.

   `column` is passed as a string and rendered raw into the SQL,
   so it can be any expression: a bare col, a cast, a function call.
#}
{% macro convert_timezone(arg1, arg2, arg3=none) %}
{%- if arg3 is none -%}
  {%- set source_tz = none -%}
  {%- set target_tz = arg1 -%}
  {%- set column = arg2 -%}
{%- else -%}
  {%- set source_tz = arg1 -%}
  {%- set target_tz = arg2 -%}
  {%- set column = arg3 -%}
{%- endif -%}
{%- if target.type == 'duckdb' -%}
  {#- DuckDB: AT TIME ZONE returns TIMESTAMPTZ; re-cast back to
      TIMESTAMP so the result type matches Snowflake's TIMESTAMP_NTZ
      default (which is what most cinch downstream models expect). -#}
  {%- if source_tz is none -%}
    {#- 2-arg form: assume col is already in UTC (cinch's session
        TZ on Snowflake is UTC), so the conversion is mostly a
        type assertion. Cast to timestamp and re-anchor at the
        target tz. -#}
    cast(cast({{ column }} as timestamp) at time zone 'UTC' at time zone '{{ target_tz }}' as timestamp)
  {%- else -%}
    cast(cast({{ column }} as timestamp) at time zone '{{ source_tz }}' at time zone '{{ target_tz }}' as timestamp)
  {%- endif -%}
{%- else -%}
  {#- Snowflake (and other adapters): emit the original
      convert_timezone() call shape verbatim. -#}
  {%- if source_tz is none -%}
    convert_timezone('{{ target_tz }}', {{ column }})
  {%- else -%}
    convert_timezone('{{ source_tz }}', '{{ target_tz }}', {{ column }})
  {%- endif -%}
{%- endif -%}
{% endmacro %}
