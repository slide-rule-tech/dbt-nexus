{{ config(materialized='table', tags=['identity-resolution', 'memberships']) }}

{% set relations_to_union = [] %}
{% for source in var('sources') %}
    {% if source.memberships %}
        {% do relations_to_union.append(ref(source.name ~ '_membership_identifiers')) %}
    {% endif %}
{% endfor %}

{% if relations_to_union %}
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

-- Return normal membership results
select
    {{ create_nexus_id('membership', ['person_id', 'group_id']) }} as membership_id,
    person_id,
    group_id,
    role,
    source,
    occurred_at,
    false as realtime_processed
from latest_memberships
where row_num = 1

{% else %}
-- Return empty result when no membership sources are configured
select
    cast(null as string) as membership_id,
    cast(null as string) as person_id,
    cast(null as string) as group_id,
    cast(null as string) as role,
    cast(null as string) as source,
    cast(null as timestamp) as occurred_at,
    cast(false as boolean) as realtime_processed
where 1 = 0
{% endif %}