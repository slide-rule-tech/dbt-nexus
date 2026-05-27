{# Cross-adapter wrapper for try_to_timestamp / try_to_timestamp_ntz.

    Snowflake forms used in cinch:
        try_to_timestamp(col)
        try_to_timestamp(col, 'MM/DD/YYYY HH24:MI:SS')
        try_to_timestamp(col, 'MM/DD/YYYY HH12:MI:SS AM')
        try_to_timestamp_ntz(col)

    DuckDB has no try_to_timestamp; closest equivalents:
        try_cast(col as timestamp)       — no format string
        try_strptime(col, '<strptime format>')  — needs translation

    Snowflake format → strptime translation:
        YYYY → %Y     MM → %m     DD → %d
        HH24 → %H     HH12 → %I   MI → %M     SS → %S
        AM   → %p

    Snowflake's behavior on parse failure: returns NULL.
    DuckDB's try_strptime / try_cast: same.
#}
{% macro try_to_timestamp(column, snowflake_format=none) %}
{%- if target.type == 'duckdb' -%}
  {%- if snowflake_format is none -%}
    try_cast({{ column }} as timestamp)
  {%- else -%}
    {%- set fmt = snowflake_format -%}
    {%- set fmt = fmt | replace('YYYY', '%Y') -%}
    {%- set fmt = fmt | replace('HH24', '%H') -%}
    {%- set fmt = fmt | replace('HH12', '%I') -%}
    {%- set fmt = fmt | replace('MM',   '%m') -%}
    {%- set fmt = fmt | replace('DD',   '%d') -%}
    {%- set fmt = fmt | replace('MI',   '%M') -%}
    {%- set fmt = fmt | replace('SS',   '%S') -%}
    {%- set fmt = fmt | replace('AM',   '%p') -%}
    try_strptime({{ column }}, '{{ fmt }}')
  {%- endif -%}
{%- else -%}
  {%- if snowflake_format is none -%}
    try_to_timestamp({{ column }})
  {%- else -%}
    try_to_timestamp({{ column }}, '{{ snowflake_format }}')
  {%- endif -%}
{%- endif -%}
{% endmacro %}


{# try_to_timestamp_ntz: same as try_to_timestamp on DuckDB
    (it has no _ntz distinction). On Snowflake, emit the _ntz variant
    so the original NTZ-typed result is preserved. #}
{% macro try_to_timestamp_ntz(column, snowflake_format=none) %}
{%- if target.type == 'duckdb' -%}
  {{ nexus.try_to_timestamp(column, snowflake_format) }}
{%- else -%}
  {%- if snowflake_format is none -%}
    try_to_timestamp_ntz({{ column }})
  {%- else -%}
    try_to_timestamp_ntz({{ column }}, '{{ snowflake_format }}')
  {%- endif -%}
{%- endif -%}
{% endmacro %}


{# to_timestamp / to_timestamp_ntz: non-try variants. Snowflake raises on
    bad input, DuckDB cast raises too. Functionally equivalent. #}
{% macro to_timestamp(column, snowflake_format=none) %}
{%- if target.type == 'duckdb' -%}
  {%- if snowflake_format is none -%}
    cast({{ column }} as timestamp)
  {%- else -%}
    {%- set fmt = snowflake_format -%}
    {%- set fmt = fmt | replace('YYYY', '%Y') -%}
    {%- set fmt = fmt | replace('HH24', '%H') -%}
    {%- set fmt = fmt | replace('HH12', '%I') -%}
    {%- set fmt = fmt | replace('MM',   '%m') -%}
    {%- set fmt = fmt | replace('DD',   '%d') -%}
    {%- set fmt = fmt | replace('MI',   '%M') -%}
    {%- set fmt = fmt | replace('SS',   '%S') -%}
    {%- set fmt = fmt | replace('AM',   '%p') -%}
    strptime({{ column }}, '{{ fmt }}')
  {%- endif -%}
{%- else -%}
  {%- if snowflake_format is none -%}
    to_timestamp({{ column }})
  {%- else -%}
    to_timestamp({{ column }}, '{{ snowflake_format }}')
  {%- endif -%}
{%- endif -%}
{% endmacro %}


{# to_timestamp_ntz: Snowflake's polymorphic to_timestamp_ntz auto-
    detects input type (string → parse, bigint → epoch micros). DuckDB
    has separate functions: cast(s as timestamp) for strings,
    make_timestamp(bigint) for micros. We can't auto-dispatch in a
    macro since input type isn't known at compile time — so callers
    pick the appropriate variant explicitly.

    nexus_to_timestamp_ntz(col)            — string / generic case
    nexus_to_timestamp_ntz_from_micros(col) — bigint epoch microseconds
#}
{% macro to_timestamp_ntz(column) %}
{%- if target.type == 'duckdb' -%}
  cast({{ column }} as timestamp)
{%- else -%}
  to_timestamp_ntz({{ column }})
{%- endif -%}
{% endmacro %}

{% macro to_timestamp_ntz_from_micros(column) %}
{%- if target.type == 'duckdb' -%}
  make_timestamp({{ column }})
{%- else -%}
  to_timestamp_ntz({{ column }})
{%- endif -%}
{% endmacro %}

{% macro to_timestamp_ntz_from_seconds(column) %}
{%- if target.type == 'duckdb' -%}
  cast(to_timestamp({{ column }}) as timestamp)
{%- else -%}
  to_timestamp_ntz({{ column }})
{%- endif -%}
{% endmacro %}
