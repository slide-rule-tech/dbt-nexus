with group_participants as (
  select * from {{ ref('group_participants') }}
),

final_groups as (
  select * from {{ ref('groups') }}
),

linked as (
  select
    p.event_id,
    p.group_id,
    g.name,
    g.domain,
    g.myshopify_domain,
    g.shop_id,
    e.occurred_at,
    e.event_name,
    e.event_description,
    e.value,
    e.value_unit,
    e.event_type,
    e.source
  from group_participants p
  left join final_groups g
    on p.group_id = g.group_id
  left join {{ ref('events') }} e
    on p.event_id = e.id
  limit 10
)

select * from linked