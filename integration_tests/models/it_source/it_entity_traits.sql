{{ config(materialized='table') }}

-- Empty-shaped traits model: the `entities` contract expects it to exist,
-- but the ER harness doesn't exercise traits (yet).
select
    cast(null as varchar) as entity_trait_id,
    cast(null as varchar) as event_id,
    cast(null as varchar) as entity_type,
    cast(null as varchar) as identifier_type,
    cast(null as varchar) as identifier_value,
    cast(null as varchar) as trait_name,
    cast(null as varchar) as trait_value,
    cast(null as varchar) as source,
    cast(null as timestamp) as occurred_at,
    cast(null as timestamp) as _ingested_at
where 1 = 0
