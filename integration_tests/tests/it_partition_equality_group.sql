{{ config(tags=["it_invariant"]) }}

-- See it_partition_equality_person.sql -- same invariant for the group
-- entity type.
with inc as (
    select identifier_type || '|' || identifier_value as ident, group_id as entity_id
    from {{ ref('nexus_resolved_group_identifiers') }}
),
sh as (
    select identifier_type || '|' || identifier_value as ident, group_id as entity_id
    from {{ ref('it_shadow_resolved_group') }}
),
missing as (
    select
        coalesce(i.ident, s.ident) as violation,
        case when i.ident is null then 'identifier missing from incremental mapping'
             else 'identifier missing from shadow (full) resolution' end as reason
    from inc i
    full outer join sh s on i.ident = s.ident
    where i.ident is null or s.ident is null
),
pairs_inc as (
    select a.ident as i1, b.ident as i2
    from inc a join inc b on a.entity_id = b.entity_id and a.ident < b.ident
),
pairs_sh as (
    select a.ident as i1, b.ident as i2
    from sh a join sh b on a.entity_id = b.entity_id and a.ident < b.ident
),
inc_only as (select i1, i2 from pairs_inc except select i1, i2 from pairs_sh),
sh_only as (select i1, i2 from pairs_sh except select i1, i2 from pairs_inc)

select violation, reason from missing
union all
select i1 || '  +  ' || i2, 'grouped incrementally but NOT in full resolution' from inc_only
union all
select i1 || '  +  ' || i2, 'grouped in full resolution but NOT incrementally' from sh_only
