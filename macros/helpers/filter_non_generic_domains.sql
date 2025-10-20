{% macro filter_non_generic_domains(domain_column) %}
    {{ domain_column }} IS NOT NULL
    AND {{ domain_column }} != ''
    {% if var('email_domain_groups_include_list', none) %}
        AND {{ domain_column }} IN UNNEST({{ var('email_domain_groups_include_list') }})
        AND {{ domain_column }} NOT IN UNNEST({{ var('email_domain_groups_exclude_list', []) }})
    {% else %}
        AND {{ domain_column }} NOT IN UNNEST({{ var('email_domain_groups_exclude_list', []) }})
    {% endif %}
{% endmacro %}
