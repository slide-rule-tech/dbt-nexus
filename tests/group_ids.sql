-- This test ensures that the number of rows in groups
-- matches the number of distinct shop_ids in shopify_partner_app_events

with groups_count as (
    select
        count(*) as total_groups
    from {{ ref('nexus_groups') }}
),

distinct_shop_ids_count as (
    select
        count(distinct shop_id) as total_distinct_shop_ids
    from {{ ref('shopify_partner_app_events') }}
),

validation as (
    select
        groups_count.total_groups as groups_count,
        distinct_shop_ids_count.total_distinct_shop_ids as distinct_shop_ids_count
    from groups_count
    cross join distinct_shop_ids_count
)

select *
from validation
where groups_count != distinct_shop_ids_count