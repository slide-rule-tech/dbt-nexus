{{ config(materialized='table', tags=['attribution', 'touchpoint-batches']) }}

with touchpoint_paths as (
    select * from {{ ref('nexus_touchpoint_paths') }}
),

touchpoint_batches as (
    {{ nexus.get_first_or_last_row(
        source='touchpoint_paths',
        partition_by='person_id, touchpoint_id',
        order_by='occurred_at',
        column_label='first_touchpoint',
        get='first'
    ) }}
)

select 
    * 
from touchpoint_batches