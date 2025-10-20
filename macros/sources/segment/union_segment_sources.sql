{%- macro union_segment_sources(table_name) -%}
    {% if var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false) and var('segment_sources', []) | length > 0 %}
        {% set segment_call_sources = [] %}
        {% for segment_source in var("segment_sources") %}
            {% set actual_table_name = var('nexus', {}).get('sources', {}).get('segment', {}).get('location', {}).get('tables', {}).get(table_name, table_name.upper()) %}
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
            split_part(_dbt_source_relation, '.', 2) as segment_source
        from unioned
    {% else %}
        -- Segment is disabled or no segment sources configured, return empty result set
        select 
            null as id,
            null as timestamp,
            null as _dbt_source_relation,
            null as segment_source
        where false
    {% endif %}
{%- endmacro -%}