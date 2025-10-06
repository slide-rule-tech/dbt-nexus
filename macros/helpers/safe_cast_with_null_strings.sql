{% macro safe_cast_with_null_strings(column_name, target_type) %}
  {% if target.type == 'snowflake' %}
    case 
      when {{ column_name }} is null then null
      when cast({{ column_name }} as string) = 'null' then null
      when cast({{ column_name }} as string) = 'NULL' then null
      when cast({{ column_name }} as string) = 'None' then null
      when cast({{ column_name }} as string) = 'none' then null
      when cast({{ column_name }} as string) = '' then null
      else try_cast(cast({{ column_name }} as string) as {{ api.Column.translate_type(target_type) }})
    end
  {% else %}
    case 
      when {{ column_name }} is null then null
      when {{ column_name }} = 'null' then null
      when {{ column_name }} = 'NULL' then null
      when {{ column_name }} = 'None' then null
      when {{ column_name }} = 'none' then null
      when {{ column_name }} = '' then null
      else {{ dbt.safe_cast(column_name, api.Column.translate_type(target_type)) }}
    end
  {% endif %}
{% endmacro %}
