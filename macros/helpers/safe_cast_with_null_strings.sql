{% macro safe_cast_with_null_strings(column_name, target_type) %}
  case 
    when {{ column_name }} is null then null
    when {{ column_name }} = 'null' then null
    when {{ column_name }} = 'NULL' then null
    when {{ column_name }} = 'None' then null
    when {{ column_name }} = 'none' then null
    when {{ column_name }} = '' then null
    else {{ dbt.safe_cast(column_name, api.Column.translate_type(target_type)) }}
  end
{% endmacro %}
