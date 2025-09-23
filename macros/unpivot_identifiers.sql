{% macro unpivot_identifiers(model_name, columns=[], additional_exclude=[], additional_columns=[], event_id_field='event_id', edge_id_field='edge_id', column_to_identifier_type={}, role_column=none, limit=none, entity_type='person') %}
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

{# Single scan approach for better performance on large tables #}
with source_data as (
  select 
    {{ event_id_field }} as event_id,
    {{ edge_id_field }} as edge_id_field_value,
    {% if role_column is not none %}
    {{ role_column }} as role,
    {% endif %}
    {% for add_col in additional_columns %}
    {{ add_col }},
    {% endfor %}
    {% for col in identifier_cols %}
    {{ col }}{% if not loop.last %},{% endif %}
    {% endfor %}
  from {{ ref(model_name) }}
  {% if target.name != 'prod' and limit is not none %}
  limit {{ limit }}
  {% endif %}
)

{% for col in identifier_cols %}
  {% if not loop.first %}union all{% endif %}
  select
    {{ nexus.create_nexus_id(entity_type ~ '_identifier', ['event_id', col, 'role', 'occurred_at']) }} as {{ entity_type }}_identifier_id,
    event_id,
    {{ nexus.create_nexus_id(entity_type ~ '_edge', ['edge_id_field_value']) }} as edge_id,
    {% if col in column_to_identifier_type %}
    '{{ column_to_identifier_type[col] }}' as identifier_type,
    {% else %}
    '{{ col }}' as identifier_type,
    {% endif %}
    cast({{ col }} as string) as identifier_value,
    {% if role_column is not none %}
    role,
    {% else %}
    cast(null as string) as role,
    {% endif %}
    {% for add_col in additional_columns %}
    {{ add_col.split(' as ')[1] if ' as ' in add_col else add_col }}{% if not loop.last %},{% endif %}
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