{% macro unpivot_identifiers(model_name) %}
{% set cols = adapter.get_columns_in_relation(ref(model_name)) %}

{# Define metadata and timestamp fields to exclude #}
{% set exclude_fields = [
  'event_id', '_dbt_source_relation', 'id',
  '_ingested_at', 'occurred_at', 'source', 'source_ingested_at', 
  'source_table', 'synced_at', 'created_at', 'updated_at'
] %}

{# Filter columns to only include actual identifier fields #}
{% set identifier_cols = [] %}
{% for col in cols %}
  {% if col.column not in exclude_fields %}
    {% do identifier_cols.append(col) %}
  {% endif %}
{% endfor %}

{# Get all column names for surrogate key generation #}
{% set all_columns = [] %}
{% for col in cols %}
  {% do all_columns.append(col.column) %}
{% endfor %}

{% for col in identifier_cols %}
  {% if not loop.first %}union all{% endif %}
  select
    event_id,
    row_id,
    '{{ col.column }}' as identifier_type,
    cast({{ col.column }} as string) as identifier_value
  from source_with_row_id
  where {{ col.column }} is not null
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