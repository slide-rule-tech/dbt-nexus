{% macro process_entity_traits(entity_type) %}


    {# Collect relations to union based on entity type #}
    {% set relations_to_union = [] %}
    {% for source in var('sources') %}
        {% if source[entity_type ~ 's'] %}
            {% do relations_to_union.append(ref(source.name ~ '_' ~ entity_type ~ '_traits')) %}
        {% endif %}
    {% endfor %}

    {% if relations_to_union %}
        with unioned as (
            {{ dbt_utils.union_relations(
                relations=relations_to_union
            ) }}
        ),
        
        normalized as (
            -- Process and standardize trait values
            select
                event_id,
                identifier_type,
                identifier_value,
                trait_name,
                trait_value,
                source,
                occurred_at
            from unioned
        )

        select
            event_id,
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
            cast(null as string) as event_id,
            cast(null as string) as identifier_type,
            cast(null as string) as identifier_value,
            cast(null as string) as trait_name,
            cast(null as string) as trait_value,
            cast(null as string) as source,
            cast(null as timestamp) as occurred_at
        where 1=0
    {% endif %}
{% endmacro %}
