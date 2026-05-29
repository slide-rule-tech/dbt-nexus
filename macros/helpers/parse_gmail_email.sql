{% macro parse_gmail_email(email_column) %}
  CASE 
    WHEN TRIM({{ email_column }}) LIKE '%<%' AND TRIM({{ email_column }}) LIKE '%>%'
    THEN REGEXP_EXTRACT(TRIM({{ email_column }}), {% if target.type == 'bigquery' %}r'<([^>]+)>'{% else %}'<([^>]+)>'{% endif %})
    ELSE TRIM({{ email_column }})
  END
{% endmacro %}