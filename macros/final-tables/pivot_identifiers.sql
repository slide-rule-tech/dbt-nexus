{% macro pivot_identifiers(identifiers_model, entity_id_column='group_id') %}
{%- set max_query %}
    select
      identifier_type,
      max(count) as max_per_entity
    from (
      select
        {{ entity_id_column }},
        identifier_type,
        count(distinct identifier_value) as count
      from {{ ref(identifiers_model) }}
      group by {{ entity_id_column }}, identifier_type
    )
    group by identifier_type
{%- endset %}

{%- set type_limits = run_query(max_query) %}
{%- set identifier_type_counts = {} %}
{%- for row in type_limits %}
  {%- set _ = identifier_type_counts.update({ row[0]: row[1] | int }) %}
{%- endfor %}

-- Single scan approach for better performance on large tables
with filtered_identifiers as (
  select
    {{ entity_id_column }},
    identifier_type,
    identifier_value
  from {{ ref(identifiers_model) }}
  where identifier_value is not null  -- Add basic filtering
),

ranked_identifiers as (
  select
    {{ entity_id_column }},
    identifier_type,
    identifier_value,
    row_number() over (
      partition by {{ entity_id_column }}, identifier_type
      order by identifier_value
    ) as rank
  from filtered_identifiers
),

pivoted as (
  select
    {{ entity_id_column }},
    {% set exprs = [] %}
    {% for type, count in identifier_type_counts.items() %}
      {% for i in range(1, count + 1) %}
        {% set col_name = type | lower | replace(' ', '_') %}
        {% set suffix = '' if i == 1 else i %}
        {% set expr = "max(case when identifier_type = '" ~ type ~ "' and rank = " ~ i ~ " then identifier_value end) as " ~ col_name ~ suffix %}
        {% do exprs.append(expr) %}
      {% endfor %}
    {% endfor %}
    {{ exprs | join(',\n    ') }}
  from ranked_identifiers
  group by {{ entity_id_column }}
)

select * from pivoted
{% endmacro %}