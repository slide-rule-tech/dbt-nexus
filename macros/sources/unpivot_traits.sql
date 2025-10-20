{% macro unpivot_traits(model_name, columns=[], identifier_column='identifier_value', identifier_type=none, additional_exclude=[], additional_columns=[], column_to_trait_name={}, event_id_field='event_id', limit=none, entity_type='person') %}
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

{# Single scan approach for better performance on large tables #}
with source_data as (
  select 
    {{ event_id_field }} as event_id,
    {{ identifier_column }} as identifier_column,
    {% for add_col in additional_columns %}
    {{ add_col }},
    {% endfor %}
    {% for col in trait_cols %}
    {{ col }}{% if not loop.last %},{% endif %}
    {% endfor %}
  from {{ ref(model_name) }}
  {% if target.name != 'prod' and limit is not none %}
  limit {{ limit }}
  {% endif %}
)

{% for col in trait_cols %}
  {% if not loop.first %}union all{% endif %}
  select
    {{ nexus.create_nexus_id('entity_trait', ['event_id', 'identifier_column', "'" ~ entity_type ~ "'", "'" ~ col ~ "'", "'" ~ (identifier_type if identifier_type is not none else identifier_column) ~ "'"]) }} as entity_trait_id,
    event_id,
    '{{ entity_type }}' as entity_type,
    {% if identifier_type is not none %}
    '{{ identifier_type }}' as identifier_type,
    {% else %}
    '{{ identifier_column }}' as identifier_type,
    {% endif %}
    {{ nexus.safe_cast_with_null_strings('identifier_column', api.Column.translate_type("string")) }} as identifier_value,
    {% if col in column_to_trait_name %}
    '{{ column_to_trait_name[col] }}' as trait_name,
    {% else %}
    '{{ col }}' as trait_name,
    {% endif %}
    {{ nexus.safe_cast_with_null_strings(col, api.Column.translate_type("string")) }} as trait_value
    {% for add_col in additional_columns %}
    , {{ add_col.split(' as ')[1] if ' as ' in add_col else add_col }}
    {% endfor %}
  from source_data
  where {{ nexus.safe_cast_with_null_strings(col, api.Column.translate_type("string")) }} is not null
{% endfor %}
{% endmacro %}