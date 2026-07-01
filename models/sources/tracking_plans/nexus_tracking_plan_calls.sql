{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('tracking_plans', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'tracking_plans', 'metadata']
) }}

-- Nexus Tracking Plan Calls — one row per documented CALL (event) in the current
-- tracking plan, per (organization_id, plan_slug). Flattens `plan.calls[]` from
-- nexus_tracking_plans. This is the queryable catalog of DOCUMENTED events — the
-- basis for the (deferred) documented-vs-fired FULL OUTER JOIN against
-- nexus_events. Warehouse-portable (Snowflake LATERAL FLATTEN vs BigQuery UNNEST).

with plans as (
    select * from {{ ref('nexus_tracking_plans') }}
)

{% if target.type == 'bigquery' %}
select
    plans.organization_id,
    plans.plan_slug,
    plans.content_hash,
    plans.last_updated_at,
    json_value(c, '$.slug') as call_slug,
    json_value(c, '$.name') as call_name,
    json_value(c, '$.fires_on') as fires_on,
    json_value(c, '$.kind') as kind,
    cast(json_value(c, '$.is_conversion') as bool) as is_conversion,
    json_value(c, '$.source') as source,
    json_value(c, '$.segment_source') as segment_source
from plans, unnest(json_query_array(plans.plan, '$.calls')) as c
{% else %}
select
    plans.organization_id,
    plans.plan_slug,
    plans.content_hash,
    plans.last_updated_at,
    c.value:slug::string as call_slug,
    c.value:name::string as call_name,
    c.value:fires_on::string as fires_on,
    c.value:kind::string as kind,
    c.value:is_conversion::boolean as is_conversion,
    c.value:source::string as source,
    c.value:segment_source::string as segment_source
from plans, lateral flatten(input => plans.plan:calls) c
{% endif %}
