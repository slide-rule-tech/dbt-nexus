{% macro redirected_domain(domain_column) %}
  CASE 
    WHEN {{ domain_column }} LIKE 'www.%' 
    THEN REGEXP_REPLACE({{ domain_column }}, '^www\\.', '')
    ELSE CONCAT('www.', {{ domain_column }})
  END
{% endmacro %}