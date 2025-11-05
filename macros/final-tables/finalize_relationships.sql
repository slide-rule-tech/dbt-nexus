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

-- Get timestamps for each relationship
relationship_timestamps as (
    select
        {{ nexus.create_nexus_id('relationship', ['entity_a_id', 'entity_b_id', 'relationship_type']) }} as relationship_id,
        min(occurred_at) as _created_at,
        max(occurred_at) as _updated_at
    from resolved_declarations
    where occurred_at is not null
    group by entity_a_id, entity_b_id, relationship_type
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
        source as primary_source,
        current_timestamp() as _processed_at,
        rt._updated_at,
        rt._created_at
    from latest_relationships lr
    left join relationship_timestamps rt
        on {{ nexus.create_nexus_id('relationship', ['lr.entity_a_id', 'lr.entity_b_id', 'lr.relationship_type']) }} = rt.relationship_id
    where lr.row_num = 1
)

select * from final_relationships

{% endmacro %}

