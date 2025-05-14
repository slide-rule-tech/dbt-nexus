{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'groups', 'realtime']) }}

{% set all_columns = get_surrogate_key_columns('manual_groups_base') %}

with numbered_rows as (
  select 
    *,
    {{ dbt_utils.generate_surrogate_key(all_columns) }} as row_id
  from {{ ref('manual_groups_base') }}
),
source_with_row_id as (
  select 
    *
  from numbered_rows
),
unpivoted_identifiers AS (
    {{ unpivot_identifiers('manual_groups_base') }}
)

SELECT
   *
FROM unpivoted_identifiers
where identifier_type in ('domain', 'myshopify_domain', 'shop_id', 'organization_id')
order by event_id desc 