{% macro resolve_entity_traits() %}

with traits as (
    select
        *
    from {{ ref('nexus_entity_traits') }}
),

-- Get all resolved entity identifiers across all entity types
all_resolved_identifiers as (
    {# Support both new unified config and legacy variable #}
    {% set entity_types = var('nexus', {}).get('entity_types') or var('nexus_entity_types', ['person', 'group']) %}
    {% for entity_type in entity_types %}
    select
        identifier_type,
        identifier_value,
        {{ entity_type }}_id as entity_id,
        '{{ entity_type }}' as entity_type
    from {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }}
    {% if not loop.last %}
    union all
    {% endif %}
    {% endfor %}
),

joined_traits as (
    select
        ei.entity_id,
        ei.entity_type,
        t.trait_name,
        t.trait_value,
        t.occurred_at
    from traits t
    join all_resolved_identifiers ei
        on t.identifier_type = ei.identifier_type
        and t.identifier_value = ei.identifier_value
        and t.entity_type = ei.entity_type
),

-- Get the latest trait values for each entity and trait name
latest_traits as (
    select
        entity_id,
        entity_type,
        trait_name,
        trait_value,
        occurred_at,
        row_number() over(
            partition by entity_id, trait_name
            order by occurred_at desc
        ) as row_num
    from joined_traits
)

select
    {{ nexus.create_nexus_id('entity_trait', ['entity_id', 'trait_name', 'trait_value']) }} as entity_trait_id,
    entity_id,
    entity_type,
    trait_name,
    trait_value,
    occurred_at,
    false as realtime_processed
from latest_traits 
where row_num = 1 
{% endmacro %}

