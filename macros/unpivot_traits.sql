{% macro unpivot_traits(model_name, columns=[], identifier_column='identifier_value', identifier_type=none, additional_exclude=[], additional_columns=[], column_to_trait_name={}, event_id_field='event_id') %}
{% set cols = adapter.get_columns_in_relation(ref(model_name)) %}

{# If no specific columns are provided, determine them from the model #}
{% if not columns %}
  {# Define metadata and common fields to exclude #}
  {% set default_exclude_fields = [
    'event_id', '_dbt_source_relation', 'id', 'occurred_at', 'synced_at',
    '_ingested_at', 'source', 'source_ingested_at', 'source_table', 'created_at', 'updated_at'
  ] %}

  {# Add identifier column to excluded fields #}
  {% set excluded_columns = default_exclude_fields + [identifier_column] + additional_exclude %}

  {# Filter columns to include only trait fields #}
  {% set trait_cols = [] %}
  {% for col in cols %}
    {% if col.column not in excluded_columns %}
      {% do trait_cols.append(col.column) %}
    {% endif %}
  {% endfor %}
{% else %}
  {# Use the explicitly provided columns #}
  {% set trait_cols = columns %}
{% endif %}

{# Set up the CTE for the source #}
with source_data as (
  select * from {{ ref(model_name) }}
)

{# Generate the UNION ALL for each trait column #}
{% for col in trait_cols %}
  {% if not loop.first %}union all{% endif %}
  select
    {{ event_id_field }} as event_id,
    {% if identifier_type is not none %}
    '{{ identifier_type }}' as identifier_type,
    {% else %}
    '{{ identifier_column }}' as identifier_type,
    {% endif %}
    {{ identifier_column }} as identifier_value,
    {% if col in column_to_trait_name %}
    '{{ column_to_trait_name[col] }}' as trait_name,
    {% else %}
    '{{ col }}' as trait_name,
    {% endif %}
    cast({{ col }} as string) as trait_value
    {% for add_col in additional_columns %}
    , {{ add_col }}
    {% endfor %}
  from source_data
  where {{ col }} is not null
{% endfor %}
{% endmacro %} 