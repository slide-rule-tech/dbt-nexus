{% macro process_event_measurements() %}
    {# Collect relations to union - sources provide event_measurements #}
    {% set relations_to_union = [] %}
    
    {# Support both new unified config and legacy list config #}
    {% set nexus_config = var('nexus', {}) %}
    {% set sources_config = nexus_config.get('sources', {}) %}
    
    {# New unified config pattern (nexus.sources dict) #}
    {% if sources_config %}
        {% for source_name, source_config in sources_config.items() %}
            {% if source_config.get('enabled') and source_config.get('measurements') %}
                {% do relations_to_union.append(ref(source_name ~ '_event_measurements')) %}
            {% endif %}
        {% endfor %}
    {# Legacy config pattern (sources list) - backward compatibility #}
    {% elif var('sources', none) %}
        {% for source in var('sources') %}
            {% if source.get('measurements') %}
                {% do relations_to_union.append(ref(source.name ~ '_event_measurements')) %}
            {% endif %}
        {% endfor %}
    {% endif %}

    {% if relations_to_union %}
        with unioned as (
            {{ dbt_utils.union_relations(
                relations=relations_to_union
            ) }}
        ),

        standardized as (
            -- Standardize dimension fields to lowercase for cross-source consistency
            select
                event_measurement_id,
                event_id,
                lower(measurement_name) as measurement_name,
                value,
                lower(value_unit) as value_unit,
                occurred_at,
                lower(source) as source
            from unioned
        )

        select
            event_measurement_id,
            event_id,
            measurement_name,
            value,
            value_unit,
            occurred_at,
            source
        from standardized
    {% else %}
        {# Return empty result if no relations found #}
        {# FROM (SELECT 1) provides a row source — BigQuery requires FROM for WHERE #}
        select 
            cast(null as string) as event_measurement_id,
            cast(null as string) as event_id,
            cast(null as string) as measurement_name,
            cast(null as {{ dbt.type_float() }}) as value,
            cast(null as string) as value_unit,
            cast(null as timestamp) as occurred_at,
            cast(null as string) as source
        from (select 1)
        where 1=0
    {% endif %}
{% endmacro %}
