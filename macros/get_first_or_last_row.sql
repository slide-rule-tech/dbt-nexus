{%- macro get_first_or_last_row(source, partition_by, order_by, column_label, get='first' ) -%}

{% set asc_or_desc = 'asc' if get == 'first' else 'desc'  %}

select
    *,
    {% if get == 'both' %}
    row_number() over (partition by {{ partition_by }} order by {{ order_by }} asc) = 1 as first_{{column_label}},
    row_number() over (partition by {{ partition_by }} order by {{ order_by }} desc) = 1 as last_{{column_label}}
    {% else %}
    row_number() over (partition by {{ partition_by }} order by {{ order_by }} {{ asc_or_desc }}) = 1 as {{column_label}}
    {% endif %}
from {{ source }}

{%- endmacro -%}