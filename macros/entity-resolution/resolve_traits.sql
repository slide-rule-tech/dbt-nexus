{% macro resolve_traits(entity_type) %}

with traits as (
    select
        *
    from {{ ref('nexus_entity_traits') }}
    where entity_type = '{{ entity_type }}'
),

entity_identifiers as (
    select
        identifier_type,
        identifier_value,
        entity_id,
        entity_type
    from {{ ref('nexus_resolved_entity_identifiers') }}
    where entity_type = '{{ entity_type }}'
),

joined_traits as (
    select
        g.entity_id,
        g.entity_type,
        t.trait_name,
        t.trait_value,
        t.occurred_at
    from traits t
    join entity_identifiers g
        on t.identifier_type = g.identifier_type
        and t.identifier_value = g.identifier_value
        and t.entity_type = g.entity_type
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
    {{ create_nexus_id('entity_trait', ['entity_id', 'trait_name', 'trait_value']) }} as entity_trait_id,
    entity_id,
    entity_type,
    trait_name,
    trait_value,
    occurred_at,
    false as realtime_processed
from latest_traits 
where row_num = 1 
{% endmacro %} 