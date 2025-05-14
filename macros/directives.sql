{% macro directives(directive_name, column_name, row_value) %}
    {%- if directive_name == 'retain_original_reference' -%}
        -- DIRECTIVE: retain original reference.
    {%- endif -%}
    {%- if directive_name == 'pivot_columns',  -%}
        -- DIRECTIVE: pivot_columns {{ column_name }} to {{ row_value }}
    {%- endif -%}
    {%- if directive_name == 'end_pivot_columns',  -%}
        -- DIRECTIVE: end_pivot_columns
    {%- endif -%}
   
{% endmacro %}
