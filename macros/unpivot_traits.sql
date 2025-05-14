{% macro unpivot_traits(model_name, identifier_columns=['identifier_value']) %}
{% set cols = adapter.get_columns_in_relation(ref(model_name)) %}
{% set excluded_columns = ['event_id', '_dbt_source_relation', 'id', 'occurred_at', 'synced_at'] %}
{% set excluded_columns = excluded_columns %}
{% set trait_cols = cols 
  | rejectattr('column', 'in', excluded_columns)
  | list %}

{% for col in trait_cols %}
  {% if not loop.first %}union all{% endif %}
  select
    event_id,
    occurred_at,
    CASE
      {% for id_col in identifier_columns %}
      WHEN {{ id_col }} IS NOT NULL THEN '{{ id_col }}'
      {% endfor %}
    END as identifier_type,
    COALESCE(
      -- DIRECTIVE: unpivot_columns trait_name to trait_value
      {% for id_col in identifier_columns %}
      {% if not loop.first %}, {% endif %}{{ id_col }}
      {% endfor %}
      -- DIRECTIVE: end_unpivot_columns
    ) as identifier_value,
    '{{ col.column }}' as trait_name,
    cast({{ col.column }} as string) as trait_value
  from {{ ref(model_name) }}
{% endfor %}
{% endmacro %} 