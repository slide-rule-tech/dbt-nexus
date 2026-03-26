{% macro process_computed_traits() %}
    {% set relations_to_union = [] %}

    {% set nexus_config = var('nexus', {}) %}
    {% set ct_list = nexus_config.get('computed_traits', []) %}

    {% for model_name in ct_list %}
        {% do relations_to_union.append(ref(model_name)) %}
    {% endfor %}

    {% if relations_to_union %}
        with unioned as (
            {{ dbt_utils.union_relations(
                relations=relations_to_union
            ) }}
        ),

        standardized as (
            select
                computed_trait_id,
                entity_id,
                lower(entity_type) as entity_type,
                lower(trait_name) as trait_name,
                trait_value,
                lower(source) as source
            from unioned
        )

        select
            computed_trait_id,
            entity_id,
            entity_type,
            trait_name,
            trait_value,
            source
        from standardized
    {% else %}
        select
            cast(null as string) as computed_trait_id,
            cast(null as string) as entity_id,
            cast(null as string) as entity_type,
            cast(null as string) as trait_name,
            cast(null as string) as trait_value,
            cast(null as string) as source
        from (select 1)
        where 1=0
    {% endif %}
{% endmacro %}
