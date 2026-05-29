{# `IN UNNEST([...])` is BigQuery syntax; Snowflake and DuckDB use the
   plain `IN (...)` form. Render the in-list as a quoted SQL tuple
   when not on BQ. #}
{% macro _domain_in_list(domain_column, values) %}
{%- if target.type == 'bigquery' -%}
{{ domain_column }} IN UNNEST({{ values }})
{%- else -%}
{{ domain_column }} IN ({%- for v in values -%}'{{ v }}'{%- if not loop.last -%},{%- endif -%}{%- endfor -%})
{%- endif -%}
{% endmacro %}

{% macro _domain_not_in_list(domain_column, values) %}
{%- if target.type == 'bigquery' -%}
{{ domain_column }} NOT IN UNNEST({{ values }})
{%- else -%}
{{ domain_column }} NOT IN ({%- for v in values -%}'{{ v }}'{%- if not loop.last -%},{%- endif -%}{%- endfor -%})
{%- endif -%}
{% endmacro %}

{% macro filter_non_generic_domains(domain_column) %}
    {{ domain_column }} IS NOT NULL
    AND {{ domain_column }} != ''
    {% if var('email_domain_groups_include_list', none) %}
        AND {{ nexus._domain_in_list(domain_column, var('email_domain_groups_include_list')) }}
        AND {{ nexus._domain_not_in_list(domain_column, var('email_domain_groups_exclude_list', [])) }}
    {% else %}
        AND {{ nexus._domain_not_in_list(domain_column, var('email_domain_groups_exclude_list', [])) }}
    {% endif %}
{% endmacro %}
