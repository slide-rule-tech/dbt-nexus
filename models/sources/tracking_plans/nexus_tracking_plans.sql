{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('tracking_plans', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'tracking_plans', 'metadata']
) }}

-- Nexus Tracking Plans — one row per (organization_id, plan_slug): the CURRENT
-- (latest-landed) version of the file-defined tracking plan, plus a small
-- summary + the raw plan payload. The collection is append-only (a row per
-- plan version), so we dedup latest-per-key by `_ingested_at`. Warehouse-portable
-- (Snowflake VARIANT vs BigQuery JSON).

with base as (
    select * from {{ ref('base_tracking_plans') }}
),

extracted as (
    select
        {% if target.type == 'bigquery' %}
        json_value(_raw_record, '$.organization_id') as organization_id,
        json_value(_raw_record, '$.plan_slug') as plan_slug,
        json_value(_raw_record, '$.content_hash') as content_hash,
        json_query(_raw_record, '$.plan') as plan,
        array_length(json_query_array(_raw_record, '$.plan.calls')) as num_calls,
        array_length(json_query_array(_raw_record, '$.plan.properties')) as num_properties,
        array_length(json_query_array(_raw_record, '$.plan.event_properties')) as num_event_properties,
        {% else %}
        _raw_record:organization_id::string as organization_id,
        _raw_record:plan_slug::string as plan_slug,
        _raw_record:content_hash::string as content_hash,
        _raw_record:plan as plan,
        array_size(_raw_record:plan:calls) as num_calls,
        array_size(_raw_record:plan:properties) as num_properties,
        array_size(_raw_record:plan:event_properties) as num_event_properties,
        {% endif %}
        _producer,
        _row_id,
        _queued_at,
        _ingested_at
    from base
),

-- Version history stats per plan (across all landed rows, before dedup).
stats as (
    select
        organization_id,
        plan_slug,
        min(_ingested_at) as first_seen_at,
        count(*) as version_rows
    from extracted
    where plan_slug is not null
    group by organization_id, plan_slug
),

-- The current version: latest row per (organization_id, plan_slug).
latest as (
    select *
    from extracted
    where plan_slug is not null
    qualify row_number() over (
        partition by organization_id, plan_slug
        order by _ingested_at desc, _row_id desc
    ) = 1
)

select
    latest.organization_id,
    latest.plan_slug,
    latest.content_hash,
    latest.num_calls,
    latest.num_properties,
    latest.num_event_properties,
    latest.plan,
    latest._producer as producer,
    stats.first_seen_at,
    latest._ingested_at as last_updated_at,
    stats.version_rows
from latest
join stats
    on stats.organization_id = latest.organization_id
    and stats.plan_slug = latest.plan_slug
