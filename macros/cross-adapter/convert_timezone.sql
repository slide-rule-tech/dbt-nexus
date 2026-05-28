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
{%- elif target.type == 'bigquery' -%}
  {#- BigQuery has no convert_timezone(). The equivalent: cast the
      column to TIMESTAMP (UTC-anchored) and then convert via the
      'AT TIME ZONE'-shape — BQ uses TIMESTAMP/DATETIME conversion
      functions. TIMESTAMP() with a tz argument constructs a UTC
      TIMESTAMP from a DATETIME interpreted in that source tz;
      DATETIME() converts a TIMESTAMP into a DATETIME at the target
      tz (giving you the "wall clock" in that zone).
      Returns TIMESTAMP (UTC-anchored) for round-trip consistency
      with the Snowflake/DuckDB branches. -#}
  {%- if source_tz is none -%}
    {#- 2-arg form: column already in UTC. Cast for safety; return
        as TIMESTAMP. The DATETIME() call returns wall-clock at
        target_tz, then TIMESTAMP(..., target_tz) re-anchors it. -#}
    timestamp(datetime(cast({{ column }} as timestamp), '{{ target_tz }}'), '{{ target_tz }}')
  {%- else -%}
    {#- 3-arg form: column wall-clock is in source_tz. Treat as a
        DATETIME (naive), build a TIMESTAMP anchored at source_tz,
        then re-anchor wall-clock to target_tz. -#}
    timestamp(datetime(timestamp(cast({{ column }} as datetime), '{{ source_tz }}'), '{{ target_tz }}'), '{{ target_tz }}')
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
