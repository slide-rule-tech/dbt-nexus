{{ config(materialized='table', tags=['identity-resolution']) }}

{# TODO: This model needs to be implemented based on the new relationships architecture #}
{# For now, return an empty result set until relationship declarations are implemented #}
select 
    cast(null as string) as relationship_id,
    cast(null as string) as entity_a_id,
    cast(null as string) as entity_a_type,
    cast(null as string) as entity_a_role,
    cast(null as string) as entity_b_id,
    cast(null as string) as entity_b_type,
    cast(null as string) as entity_b_role,
    cast(null as string) as relationship_type,
    cast(null as string) as relationship_direction,
    cast(null as boolean) as is_primary,
    cast(null as boolean) as is_active,
    cast(null as float) as interaction_score,
    cast(null as integer) as email_interactions,
    cast(null as integer) as meeting_interactions,
    cast(null as integer) as total_interactions,
    cast(null as timestamp) as first_interaction_at,
    cast(null as timestamp) as last_interaction_at,
    cast(null as timestamp) as established_at,
    cast(null as timestamp) as last_updated_at,
    cast(null as string) as primary_source,
    cast(null as timestamp) as _last_calculated
where 1=0
