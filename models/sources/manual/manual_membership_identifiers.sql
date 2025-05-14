{{ config(materialized='view', tags=['identity-resolution',  'memberships', 'realtime']) }}

select
    *,
    "manual" as source
from {{ ref('manual_memberships_base') }}

