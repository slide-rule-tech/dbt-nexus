{{ config(materialized='table', tags=['identity-resolution', 'memberships']) }}

with membership_identifiers as (
    select * from {{ ref('nexus_membership_identifiers') }}
),

-- Person and group resolved identifiers
person_identifiers as (
    select * from {{ ref('nexus_resolved_person_identifiers') }}
),

group_identifiers as (
    select * from {{ ref('nexus_resolved_group_identifiers') }}
),

-- Join person identifiers to membership
membership_with_person_id as (
    select
        m.event_id,
        m.occurred_at,
        m.person_identifier,
        m.person_identifier_type,
        m.group_identifier,
        m.group_identifier_type,
        m.role,
        m.source,
        p.person_id
    from membership_identifiers m
    left join person_identifiers p
        on m.person_identifier = p.identifier_value
        and m.person_identifier_type = p.identifier_type
),

-- Join group identifiers to membership
resolved_memberships as (
    select
        m.event_id,
        m.occurred_at,
        m.person_id,
        g.group_id,
        m.role,
        m.source
    from membership_with_person_id m
    left join group_identifiers g
        on m.group_identifier = g.identifier_value
        and m.group_identifier_type = g.identifier_type
    where
        m.person_id is not null and
        g.group_id is not null
),

-- Get the latest membership information for each person-group combination
latest_memberships as (
    select
        event_id,
        occurred_at,
        person_id,
        group_id,
        role,
        source,
        row_number() over(
            partition by person_id, group_id
            order by occurred_at desc
        ) as row_num
    from resolved_memberships
)

select
    {{ dbt_utils.generate_surrogate_key(['person_id', 'group_id']) }} as membership_id,
    person_id,
    group_id,
    role,
    source,
    occurred_at,
    false as realtime_processed
from latest_memberships
where row_num = 1