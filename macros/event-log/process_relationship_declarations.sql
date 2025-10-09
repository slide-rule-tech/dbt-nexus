{% macro process_relationship_declarations() %}
    {# Collect relations to union - sources provide relationship_declarations #}
    {% set relations_to_union = [] %}
    
    {# Support both new unified config and legacy list config #}
    {% set nexus_config = var('nexus', {}) %}
    {% set sources_config = nexus_config.get('sources', {}) %}
    
    {# New unified config pattern (nexus.sources dict) #}
    {% if sources_config %}
        {% for source_name, source_config in sources_config.items() %}
            {% if source_config.get('enabled') and source_config.get('relationships') %}
                {% do relations_to_union.append(ref(source_name ~ '_relationship_declarations')) %}
            {% endif %}
        {% endfor %}
    {# Legacy config pattern (sources list) - backward compatibility #}
    {% elif var('sources', none) %}
        {% for source in var('sources') %}
            {% if source.get('relationships') %}
                {% do relations_to_union.append(ref(source.name ~ '_relationship_declarations')) %}
            {% endif %}
        {% endfor %}
    {% endif %}

    {% if relations_to_union %}
        with unioned as (
            {{ dbt_utils.union_relations(
                relations=relations_to_union
            ) }}
        )

        select
            relationship_declaration_id,
            event_id,
            occurred_at,
            entity_a_identifier,
            entity_a_identifier_type,
            entity_a_type,
            entity_a_role,
            entity_b_identifier,
            entity_b_identifier_type,
            entity_b_type,
            entity_b_role,
            relationship_type,
            relationship_direction,
            is_active,
            source
        from unioned
    {% else %}
        {# Return empty result if no relations found #}
        select 
            cast(null as string) as relationship_declaration_id,
            cast(null as string) as event_id,
            cast(null as timestamp) as occurred_at,
            cast(null as string) as entity_a_identifier,
            cast(null as string) as entity_a_identifier_type,
            cast(null as string) as entity_a_type,
            cast(null as string) as entity_a_role,
            cast(null as string) as entity_b_identifier,
            cast(null as string) as entity_b_identifier_type,
            cast(null as string) as entity_b_type,
            cast(null as string) as entity_b_role,
            cast(null as string) as relationship_type,
            cast(null as string) as relationship_direction,
            cast(null as boolean) as is_active,
            cast(null as string) as source
        where 1=0
    {% endif %}
{% endmacro %}

