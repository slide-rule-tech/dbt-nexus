{# Cross-adapter regex helpers. #}

{# Extract a single capture group from a regex match.

    Snowflake: REGEXP_SUBSTR(str, pattern, position, occurrence, parameters, group_num)
        e.g., REGEXP_SUBSTR(col, 'OPT-(\\d+)', 1, 1, 'e', 1) → capture group 1
        (NOTE: Snowflake string literals interpret `\\` as `\`, so a
         regex `\d` requires `'\\d'` in source SQL.)

    DuckDB: regexp_extract(str, pattern, group_idx)
        e.g., regexp_extract(col, 'OPT-(\d+)', 1) → capture group 1
        (DuckDB string literals do NOT interpret backslashes — `'\d'`
         is the 2-char string `\d`, and the regex engine sees `\d`.)

    BigQuery: REGEXP_EXTRACT(str, pattern) returns capture group 1.
        For group N > 1 BQ has no direct equivalent — we wrap the
        pattern in (?:...) for the leading groups so the user's
        target group lands as group 1. Specifically: take the input
        pattern as "<prefix>(target)<suffix>" where target is the
        Nth capture group, and rewrite to a pattern that only
        captures target. This is approximate — fully general pattern
        rewriting would need a real regex parser. For now the BQ
        branch only supports group_num=1; groups > 1 raise.

    Usage:
      {{ nexus.regexp_extract_group('col', 'OPT-(\\d+)\\((.*)\\)', 2) }}

    The `pattern` arg should be written with `\\` for each regex
    backslash (Jinja string-escape rules). The macro auto-doubles
    backslashes again on Snowflake so the resulting SQL string literal
    decodes back to a single backslash in the regex.
#}
{% macro regexp_extract_group(column, pattern, group_num=1) %}
{%- if target.type == 'duckdb' -%}
  regexp_extract({{ column }}, '{{ pattern }}', {{ group_num }})
{%- elif target.type == 'snowflake' -%}
  {%- set sf_pattern = pattern | replace('\\', '\\\\') -%}
  regexp_substr({{ column }}, '{{ sf_pattern }}', 1, 1, 'e', {{ group_num }})
{%- elif target.type == 'bigquery' -%}
  {%- if group_num != 1 -%}
    {{ exceptions.raise_compiler_error("nexus.regexp_extract_group() on BigQuery only supports group_num=1; for group N>1, rewrite the pattern so the target capture is the first group (wrap other groups as (?:...)) or use BQ's REGEXP_EXTRACT_ALL with offset.") }}
  {%- endif -%}
  regexp_extract({{ column }}, r'{{ pattern }}')
{%- else -%}
  {{ exceptions.raise_compiler_error("nexus.regexp_extract_group() does not support target.type='" ~ target.type ~ "' yet") }}
{%- endif -%}
{% endmacro %}
