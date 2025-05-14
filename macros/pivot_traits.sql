{% macro pivot_traits(traits_model, entity_id_column='group_id', prefix='traits_') %}

{%- set trait_names = dbt_utils.get_column_values(
    ref(traits_model),
    'trait_name'
) | default([]) -%}

SELECT
  -- DIRECTIVE: pivot_columns trait_name to trait_value
  {% if trait_names %}
    {% for trait in trait_names %}
    max(case when trait_name = '{{ trait }}' then trait_value end) as {{ trait | replace(' ', '_') | lower }},
    {% endfor %}
    
  {% endif %}
   -- DIRECTIVE: end_pivot_columns
  {{ entity_id_column }} as {{ prefix }}{{ entity_id_column }}
  
FROM {{ ref(traits_model) }}
group by {{ entity_id_column }}
{% endmacro %}