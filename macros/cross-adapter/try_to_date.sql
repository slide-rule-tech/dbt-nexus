{# Cross-adapter wrapper for try_to_date / to_date.

    Snowflake forms used in cinch (and similar warehouses):
        try_to_date(col)
        try_to_date(col, 'MM-DD-YYYY')
        try_to_date(col, 'YYYY-MM-DD')

    DuckDB has no try_to_date. Equivalents:
        try_cast(col as date)              — no format string
        try_strptime(col, '<fmt>')::date   — needs Snowflake→strptime translation

    Snowflake format → strptime translation (same rules as try_to_timestamp):
        YYYY → %Y     MM → %m     DD → %d

    Both adapters return NULL on parse failure for the try_ variants.
#}
{% macro try_to_date(column, snowflake_format=none) %}
{%- if target.type == 'duckdb' -%}
  {%- if snowflake_format is none -%}
    try_cast({{ column }} as date)
  {%- else -%}
    {%- set fmt = snowflake_format -%}
    {%- set fmt = fmt | replace('YYYY', '%Y') -%}
    {%- set fmt = fmt | replace('MM',   '%m') -%}
    {%- set fmt = fmt | replace('DD',   '%d') -%}
    try_cast(try_strptime({{ column }}, '{{ fmt }}') as date)
  {%- endif -%}
{%- else -%}
  {%- if snowflake_format is none -%}
    try_to_date({{ column }})
  {%- else -%}
    try_to_date({{ column }}, '{{ snowflake_format }}')
  {%- endif -%}
{%- endif -%}
{% endmacro %}


{# Non-try variant: raises on bad input on both Snowflake and DuckDB. #}
{% macro to_date(column, snowflake_format=none) %}
{%- if target.type == 'duckdb' -%}
  {%- if snowflake_format is none -%}
    cast({{ column }} as date)
  {%- else -%}
    {%- set fmt = snowflake_format -%}
    {%- set fmt = fmt | replace('YYYY', '%Y') -%}
    {%- set fmt = fmt | replace('MM',   '%m') -%}
    {%- set fmt = fmt | replace('DD',   '%d') -%}
    cast(strptime({{ column }}, '{{ fmt }}') as date)
  {%- endif -%}
{%- else -%}
  {%- if snowflake_format is none -%}
    to_date({{ column }})
  {%- else -%}
    to_date({{ column }}, '{{ snowflake_format }}')
  {%- endif -%}
{%- endif -%}
{% endmacro %}
