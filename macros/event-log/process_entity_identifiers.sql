{% macro process_entity_identifiers() %}
    {# Collect relations to union - now sources provide unified entity_identifiers #}
    {% set relations_to_union = [] %}
    {% for source in var('sources') %}
        {% if source.get('entities') %}
            {% do relations_to_union.append(ref(source.name ~ '_entity_identifiers')) %}
        {% endif %}
    {% endfor %}

    {% if relations_to_union %}
        with unioned as (
            {{ dbt_utils.union_relations(
                relations=relations_to_union
            ) }}
        ),
        
        normalized as (
            -- Standardize identifier formats (lowercase emails, etc.)
            select
                entity_identifier_id,
                event_id,
                edge_id,
                entity_type,
                identifier_type,
                identifier_value,
                -- Normalize identifier values based on type
                case
                    when identifier_type = 'email' then lower(identifier_value)
                    when identifier_type = 'phone' then regexp_replace(identifier_value, '[^0-9]', '') -- Keep only digits
                    when identifier_type = 'domain' then lower(identifier_value)
                    else identifier_value
                end as normalized_value,
                role,
                source,
                occurred_at
            from unioned
        )

        select
            entity_identifier_id,
            event_id,
            edge_id,
            entity_type,
            identifier_type,
            identifier_value,
            normalized_value,
            role,
            source,
            occurred_at
        from normalized
    {% else %}
        {# Return empty result if no relations found #}
        select 
            cast(null as string) as entity_identifier_id,
            cast(null as string) as event_id,
            cast(null as string) as edge_id,
            cast(null as string) as entity_type,
            cast(null as string) as identifier_type,
            cast(null as string) as identifier_value,
            cast(null as string) as normalized_value,
            cast(null as string) as role,
            cast(null as string) as source,
            cast(null as timestamp) as occurred_at
        where 1=0
    {% endif %}
{% endmacro %}
