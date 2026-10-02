{% macro gmail_header_value(raw_record_column, header_name) -%}
  {#-
    Pull a single header value out of a Gmail `_raw_record`'s `$.headers`
    array (an array of {name, value} objects).

    Header names are matched case-INSENSITIVELY, because the Gmail API
    returns whatever casing the sending MTA used (`Message-ID` vs
    `Message-Id`, `X-Failed-Recipients` vs `X-failed-recipients`).

    Returns the FIRST match, or NULL when the header is absent. Headers
    that legitimately repeat (Received, Return-Path) are not served by
    this macro.

    Usage:
      {{ nexus.gmail_header_value('m.raw_record', 'x-failed-recipients') }}
  -#}
  (SELECT JSON_EXTRACT_SCALAR(header, '$.value')
   FROM {% if target.type == 'duckdb' %}UNNEST(JSON_EXTRACT_ARRAY({{ raw_record_column }}, '$.headers')) as t(header){% else %}UNNEST(JSON_EXTRACT_ARRAY({{ raw_record_column }}, '$.headers')) as header{% endif %}
   WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = '{{ header_name | lower }}'
   LIMIT 1)
{%- endmacro %}
