{%- macro case_map(column, mapping) -%}
case
    {%- for key, value in mapping.items() if key != 'default' %}
    when {{ column }} = '{{ key }}' then {{ value }}
    {%- endfor %}
    else {{ mapping.get('default', 'null') }}
end
{%- endmacro -%}
