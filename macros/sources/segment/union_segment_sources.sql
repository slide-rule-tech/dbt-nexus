{%- macro union_segment_sources(table_name) -%}
    {% set segment_call_sources = [] %}
    {% for segment_source in var("segment_sources") %}
        {% set actual_table_name = var('nexus', {}).get('segment', {}).get('location', {}).get('tables', {}).get(table_name, table_name.upper()) %}
        {% do segment_call_sources.append(source(segment_source.name, actual_table_name)) %}
    {% endfor %}

    with unioned as (
        {{ dbt_utils.union_relations(
            relations=segment_call_sources,
            source_column_name='_dbt_source_relation'
        ) }}
    )

    select 
        *,
        case 
            when _dbt_source_relation like '%WORDPRESS_SITE%' then 'WORDPRESS_SITE'
            when _dbt_source_relation like '%SERVER_AWS_LAMBDA_TRACKING%' then 'SERVER_AWS_LAMBDA_TRACKING'
            else split_part(_dbt_source_relation, '.', 2)
        end as segment_source
    from unioned
{%- endmacro -%}