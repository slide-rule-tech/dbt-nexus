{% macro finalize_relationships() %}

with resolved_declarations as (
    select * from {{ ref('nexus_resolved_relationship_declarations') }}
),

-- Get the most recent state for each unique relationship
latest_relationships as (
    select
        entity_a_id,
        entity_a_type,
        entity_a_role,
        entity_b_id,
        entity_b_type,
        entity_b_role,
        relationship_type,
        relationship_direction,
        is_active,
        source,
        occurred_at,
        row_number() over(
            partition by entity_a_id, entity_b_id, relationship_type
            order by occurred_at desc
        ) as row_num
    from resolved_declarations
),

final_relationships as (
    select
        {{ nexus.create_nexus_id('relationship', ['entity_a_id', 'entity_b_id', 'relationship_type']) }} as relationship_id,
        entity_a_id,
        entity_a_type,
        entity_a_role,
        entity_b_id,
        entity_b_type,
        entity_b_role,
        relationship_type,
        relationship_direction,
        is_active,
        occurred_at as established_at,
        occurred_at as last_updated_at,
        source as primary_source
    from latest_relationships
    where row_num = 1
)

select * from final_relationships

{% endmacro %}

