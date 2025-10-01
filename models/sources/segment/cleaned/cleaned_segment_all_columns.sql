{%- set columns = adapter.get_columns_in_relation(ref('base_segment_all_calls')) -%}

select
{% for column in columns %}
  {%- if column.name.lower() in ['email', 'email_address'] -%}
    {{ nexus.validate_and_normalize_email(column.name) }} as {{ column.name }}{% if not loop.last %},{% endif %}
  {%- elif column.name.lower() in ['phone', 'phone_number', 'mobile', 'mobile_number'] -%}
    {{ nexus.validate_and_normalize_phone(column.name) }} as {{ column.name }}{% if not loop.last %},{% endif %}
  {%- else -%}
    {{ column.name }}{% if not loop.last %},{% endif %}
  {%- endif -%}
{% endfor %}
from {{ ref('base_segment_all_calls') }}