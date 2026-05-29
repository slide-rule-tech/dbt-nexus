{% macro extract_gmail_name(email_column) %}
  CASE 
    WHEN TRIM({{ email_column }}) LIKE '%<%' AND TRIM({{ email_column }}) LIKE '%>%'
    THEN TRIM({% if target.type == 'bigquery' %}REGEXP_EXTRACT(TRIM({{ email_column }}), r'^([^<]+)<'){% else %}regexp_extract(TRIM({{ email_column }}), '^([^<]+)<', 1){% endif %})
    ELSE NULL
  END
{% endmacro %}