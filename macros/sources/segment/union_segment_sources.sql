{%- macro union_segment_sources(table_name, column_override=none) -%}
    {% if var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false) and var('segment_sources', []) | length > 0 %}
        {# Build list of sources, filtering by table availability #}
        {% set segment_call_sources = [] %}
        {% for segment_source in var("segment_sources") %}
            {# If source defines a 'tables' list, only include if table_name is in it #}
            {% set source_tables = segment_source.get('tables', none) %}
            {% if source_tables is none or table_name.lower() in source_tables %}
                {% set actual_table_name = var('nexus', {}).get('sources', {}).get('segment', {}).get('location', {}).get('tables', {}).get(table_name, table_name.upper()) %}
                {% do segment_call_sources.append(source(segment_source.name, actual_table_name)) %}
            {% endif %}
        {% endfor %}

        {% if segment_call_sources | length > 0 %}
        with unioned as (
            {{ dbt_utils.union_relations(
                relations=segment_call_sources,
                source_column_name='_dbt_source_relation',
                column_override=column_override if column_override else {}
            ) }}
        ),

        with_segment_source as (
            select 
                *,
                {% if target.type == 'bigquery' %}
                REGEXP_EXTRACT(_dbt_source_relation, r'`[^`]+`\.`([^`]+)`\.') as segment_source
                {% else %}
                SPLIT_PART(_dbt_source_relation, '.', 2) as segment_source
                {% endif %}
            from unioned
        )

        -- Deduplicate: Segment can deliver duplicate events
        select * from with_segment_source
        qualify ROW_NUMBER() over (partition by id, segment_source order by received_at desc) = 1
        {% else %}
        -- No sources have the '{{ table_name }}' table, return empty result set
        select 
            cast(null as string) as id,
            cast(null as timestamp) as timestamp,
            cast(null as string) as _dbt_source_relation,
            cast(null as string) as segment_source
        where false
        {% endif %}
    {% elif var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false) %}
        {# Single-source fallback: segment is enabled but no segment_sources var defined #}
        select 
            *,
            cast(null as string) as segment_source
        from {{ nexus.nexus_source('segment', table_name) }}
    {% else %}
        -- Segment is disabled, return empty result set
        select 
            cast(null as string) as id,
            cast(null as timestamp) as timestamp,
            cast(null as string) as _dbt_source_relation,
            cast(null as string) as segment_source
        where false
    {% endif %}
{%- endmacro -%}