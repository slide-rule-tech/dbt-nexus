{% macro process_event_dimensions() %}
    {# Collect relations to union - sources provide event_dimensions #}
    {% set relations_to_union = [] %}
    
    {# Support both new unified config and legacy list config #}
    {% set nexus_config = var('nexus', {}) %}
    {% set sources_config = nexus_config.get('sources', {}) %}
    
    {# New unified config pattern (nexus.sources dict) #}
    {% if sources_config %}
        {% for source_name, source_config in sources_config.items() %}
            {% if source_config.get('enabled') and source_config.get('dimensions') %}
                {% do relations_to_union.append(ref(source_name ~ '_event_dimensions')) %}
            {% endif %}
        {% endfor %}
    {# Legacy config pattern (sources list) - backward compatibility #}
    {% elif var('sources', none) %}
        {% for source in var('sources') %}
            {% if source.get('dimensions') %}
                {% do relations_to_union.append(ref(source.name ~ '_event_dimensions')) %}
            {% endif %}
        {% endfor %}
    {% endif %}

    {% if relations_to_union %}
        {{ nexus.nexus_incremental_require_ingested_at(relations_to_union, 'nexus_event_dimensions') }}
        with unioned as (
            {{ dbt_utils.union_relations(
                relations=relations_to_union
            ) }}
        ),

        standardized as (
            select
                event_dimension_id,
                event_id,
                lower(dimension_name) as dimension_name,
                dimension_value,
                occurred_at,
                lower(source) as source,
                _ingested_at
            from unioned
        )

        select
            event_dimension_id,
            event_id,
            dimension_name,
            dimension_value,
            occurred_at,
            source,
            _ingested_at
        from standardized
        {% if is_incremental() %}
        where _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
        qualify row_number() over (partition by event_dimension_id order by _ingested_at desc) = 1
        {% endif %}
    {% else %}
        {# Return empty result if no relations found #}
        {# FROM (SELECT 1) provides a row source — BigQuery requires FROM for WHERE #}
        select 
            cast(null as string) as event_dimension_id,
            cast(null as string) as event_id,
            cast(null as string) as dimension_name,
            cast(null as string) as dimension_value,
            cast(null as timestamp) as occurred_at,
            cast(null as string) as source,
            cast(null as timestamp) as _ingested_at
        from (select 1)
        where 1=0
    {% endif %}
{% endmacro %}
