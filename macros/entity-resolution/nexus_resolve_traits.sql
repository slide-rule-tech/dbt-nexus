{% macro nexus_resolve_traits(entity_type) %}

with traits as (
    select
        *
    from {{ ref(entity_type ~ '_traits') }}
),

entity_identifiers as (
    select
        identifier_type,
        identifier_value,
        {{ entity_type }}_id
    from {{ ref('resolved_' ~ entity_type ~ '_identifiers') }}
),

joined_traits as (
    select
        g.{{ entity_type }}_id,
        t.trait_name,
        t.trait_value,
        t.occurred_at
    from traits t
    join entity_identifiers g
        on t.identifier_type = g.identifier_type
        and t.identifier_value = g.identifier_value
),

-- Get the latest trait values for each entity and trait name
latest_traits as (
    select
        {{ entity_type }}_id,
        trait_name,
        trait_value,
        occurred_at,
        row_number() over(
            partition by {{ entity_type }}_id, trait_name
            order by occurred_at desc
        ) as row_num
    from joined_traits
)

select
    {{ dbt_utils.generate_surrogate_key([entity_type ~ '_id', 'trait_name', 'trait_value']) }} as trait_id,
    {{ entity_type }}_id,
    trait_name,
    trait_value,
    occurred_at,
    false as realtime_processed
from latest_traits 
where row_num = 1 
{% endmacro %} 