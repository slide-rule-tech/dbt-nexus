{%- macro union_segment_sources(table_name) -%}
    {% set segment_call_sources = [] %}
    {% for segment_source in var("segment_sources") %}
        {% set actual_table_name = var('nexus', {}).get('segment', {}).get('location', {}).get('tables', {}).get(table_name, table_name.upper()) %}
        {% do segment_call_sources.append(source(segment_source.name, actual_table_name)) %}
    {% endfor %}

    {% for relation in segment_call_sources %}
        (
            select 
                *,
                '{{ relation.schema }}' as segment_source
            from {{ relation }}
        )
        {% if not loop.last %}
        union all
        {% endif %}
    {% endfor %}
{%- endmacro -%}