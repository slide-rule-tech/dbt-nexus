{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('tracking_plans', {}).get('enabled', false),
    materialized='view',
    tags=['nexus', 'tracking_plans', 'base']
) }}

-- Passthrough of the raw `tracking_plans` BBP collection. Gated by
-- var('nexus').sources.tracking_plans.enabled so it's a no-op for clients that
-- don't have a tracking plan projected.
select * from {{ source('tracking_plans', 'tracking_plans') }}
