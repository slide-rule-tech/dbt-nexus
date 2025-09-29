{{ config(
    enabled=var('nexus', {}).get('attribution_models', {}).get('last_fbclid', {}).get('enabled', false),
    materialized='table', 
    tags=['attribution', 'fbclid', 'template-attribution-model']
) }}

{#
This model finds the last fbclid for each batch by looking back through 
the person's touchpoint history. For each batch, it identifies the most 
recent previous batch (for the same person) that contains an fbclid value.

The approach uses a window function to find the most recent previous batch with fbclid
for each person, then assigns that fbclid to all subsequent batches until 
a new fbclid is encountered.
#}

with touchpoint_batches as (
    select * from {{ ref('nexus_touchpoint_path_batches') }}
),

-- Create a complete timeline for each person with all batches
person_timeline as (
    select
        touchpoint_batch_id,
        person_id,
        touchpoint_occurred_at,
        touchpoint_event_id,
        fbclid,
        row_number() over (
            partition by person_id 
            order by touchpoint_occurred_at
        ) as batch_sequence
    from touchpoint_batches
),

-- Use window function to carry forward the last fbclid for each person
last_fbclid_attribution as (
    select
        touchpoint_batch_id,
        person_id,
        touchpoint_occurred_at,
        touchpoint_event_id,
        fbclid,
        -- Carry forward the last non-null fbclid for this person
        last_value(fbclid ignore nulls) over (
            partition by person_id 
            order by touchpoint_occurred_at
            rows between unbounded preceding and current row
        ) as last_fbclid
    from person_timeline
),

-- Join with nexus_touchpoint_paths to get all event_ids for each batch
touchpoint_paths as (
    select 
        touchpoint_batch_id,
        event_id,
        person_id,
        event_occurred_at
    from {{ ref('nexus_touchpoint_paths') }}
),

-- Final output: attribution model results with metadata
final_output as (
    select
        {{ nexus.create_nexus_id('attribution_model_result', ['lf.touchpoint_batch_id', 'tp.event_id', 'lf.person_id']) }} as attribution_model_result_id,
        lf.touchpoint_occurred_at,
        'last_fbclid' as attribution_model_name,
        lf.touchpoint_batch_id,
        lf.touchpoint_event_id,
        tp.event_id as attributed_event_id,
        lf.person_id,
        tp.event_occurred_at as attributed_event_occurred_at,
        lf.last_fbclid as fbclid
    from last_fbclid_attribution lf
    inner join touchpoint_paths tp
        on lf.touchpoint_batch_id = tp.touchpoint_batch_id
        and lf.person_id = tp.person_id
)

select * from final_output
order by person_id, touchpoint_occurred_at, attributed_event_id
