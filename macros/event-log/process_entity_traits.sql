{% macro process_entity_traits() %}
    {# Collect relations to union - now sources provide unified entity_traits #}
    {% set relations_to_union = [] %}
    
    {# Support both new unified config and legacy list config #}
    {% set nexus_config = var('nexus', {}) %}
    {% set sources_config = nexus_config.get('sources', {}) %}
    
    {# New unified config pattern (nexus.sources dict) #}
    {% if sources_config %}
        {% for source_name, source_config in sources_config.items() %}
            {% if source_config.get('enabled') and source_config.get('entities') %}
                {% do relations_to_union.append(ref(source_name ~ '_entity_traits')) %}
            {% endif %}
        {% endfor %}
    {# Legacy config pattern (sources list) - backward compatibility #}
    {% elif var('sources', none) %}
        {% for source in var('sources') %}
            {% if source.get('entities') %}
                {% do relations_to_union.append(ref(source.name ~ '_entity_traits')) %}
            {% endif %}
        {% endfor %}
    {% endif %}

    {% if relations_to_union %}
        with unioned as (
            {{ dbt_utils.union_relations(
                relations=relations_to_union
            ) }}
        ),
        
        normalized as (
            -- Process and standardize trait values
            select
                entity_trait_id,
                event_id,
                entity_type,
                identifier_type,
                identifier_value,
                trait_name,
                trait_value,
                source,
                occurred_at
            from unioned
        )

        select
            entity_trait_id,
            event_id,
            entity_type,
            identifier_type,
            identifier_value,
            trait_name,
            trait_value,
            source,
            occurred_at
        from normalized
    {% else %}
        {# Return empty result if no relations found #}
        select 
            cast(null as string) as entity_trait_id,
            cast(null as string) as event_id,
            cast(null as string) as entity_type,
            cast(null as string) as identifier_type,
            cast(null as string) as identifier_value,
            cast(null as string) as trait_name,
            cast(null as string) as trait_value,
            cast(null as string) as source,
            cast(null as timestamp) as occurred_at
        where 1=0
    {% endif %}
{% endmacro %}
