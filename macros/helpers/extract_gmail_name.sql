{% macro extract_gmail_name(email_column) %}
  CASE 
    WHEN TRIM({{ email_column }}) LIKE '%<%' AND TRIM({{ email_column }}) LIKE '%>%'
    THEN TRIM(REGEXP_EXTRACT(TRIM({{ email_column }}), r'^([^<]+)<'))
    ELSE NULL
  END
{% endmacro %}