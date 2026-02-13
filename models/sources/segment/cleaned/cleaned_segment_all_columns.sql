{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false)
) }}

{%- set columns = adapter.get_columns_in_relation(ref('base_segment_all_calls')) -%}

select
{% for column in columns %}
  {%- if column.name.lower() in ['email', 'email_address'] -%}
    {{ nexus.validate_and_normalize_email(adapter.quote(column.name)) }} as {{ adapter.quote(column.name) }}{% if not loop.last %},{% endif %}
  {%- elif column.name.lower() in ['phone', 'phone_number', 'mobile', 'mobile_number'] -%}
    {{ nexus.validate_and_normalize_phone(adapter.quote(column.name)) }} as {{ adapter.quote(column.name) }}{% if not loop.last %},{% endif %}
  {%- else -%}
    {{ adapter.quote(column.name) }}{% if not loop.last %},{% endif %}
  {%- endif -%}
{% endfor %}
from {{ ref('base_segment_all_calls') }}