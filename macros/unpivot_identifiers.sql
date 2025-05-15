{% macro unpivot_identifiers(model_name, columns=[], additional_exclude=[], additional_columns=[], event_id_field='event_id', row_id_field='row_id', column_to_identifier_type={}) %}
{% set cols = adapter.get_columns_in_relation(ref(model_name)) %}

{# If no specific columns are provided, determine them from the model #}
{% if not columns %}
  {# Define metadata and timestamp fields to exclude #}
  {% set default_exclude_fields = [
    'event_id', '_dbt_source_relation', 'id',
    '_ingested_at', 'occurred_at', 'source', 'source_ingested_at', 
    'source_table', 'synced_at', 'created_at', 'updated_at'
  ] %}

  {# Merge default exclude fields with additional exclude fields #}
  {% set exclude_fields = default_exclude_fields + additional_exclude %}

  {# Filter columns to only include actual identifier fields #}
  {% set identifier_cols = [] %}
  {% for col in cols %}
    {% if col.column not in exclude_fields %}
      {% do identifier_cols.append(col.column) %}
    {% endif %}
  {% endfor %}
{% else %}
  {# Use the explicitly provided columns #}
  {% set identifier_cols = columns %}
{% endif %}

{# Set up the CTE for the source #}
with source_data as (
  select * from {{ ref(model_name) }}
)

{# Generate the UNION ALL for each identifier column #}
{% for col in identifier_cols %}
  {% if not loop.first %}union all{% endif %}
  select
    {{ event_id_field }} as event_id,
    {{ row_id_field }} as row_id,
    {% if col in column_to_identifier_type %}
    '{{ column_to_identifier_type[col] }}' as identifier_type,
    {% else %}
    '{{ col }}' as identifier_type,
    {% endif %}
    cast({{ col }} as string) as identifier_value
    {% for add_col in additional_columns %}
    , {{ add_col }}
    {% endfor %}
  from source_data
  where {{ col }} is not null
{% endfor %}
{% endmacro %}

{% macro get_surrogate_key_columns(model_name) %}
{% set cols = adapter.get_columns_in_relation(ref(model_name)) %}
{% set all_columns = [] %}
{% for col in cols %}
  {% do all_columns.append(col.column) %}
{% endfor %}
{{ return(all_columns) }}
{% endmacro %}