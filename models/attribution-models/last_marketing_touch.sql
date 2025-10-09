{{ config(
    enabled=var('nexus', {}).get('attribution_models', {}).get('last_marketing_touch', {}).get('enabled', false),
    materialized='table', 
    tags=['attribution', 'marketing', 'template-attribution-model']
) }}

{#
This model provides last-touch marketing attribution. Since touchpoint sources 
already filter out records with all null attribution fields, each touchpoint 
in nexus_touchpoint_path_batches has at least one non-null attribution field.

This model simply uses the touchpoint data directly - the "last touch" logic is 
already handled by nexus_touchpoint_paths which assigns each event to its most 
recent preceding touchpoint.
#}

with touchpoint_batches as (
    select * from {{ ref('nexus_touchpoint_path_batches') }}
),

-- Filter for web marketing touchpoints only
web_touchpoints as (
    select
        touchpoint_batch_id,
        person_id,
        touchpoint_occurred_at,
        touchpoint_event_id,
        -- Attribution fields (already cleaned in source touchpoints)
        source,
        medium,
        campaign,
        content,
        gclid,
        touchpoint_type
    from touchpoint_batches
    where touchpoint_type = 'web'
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
        {{ nexus.create_nexus_id('attribution_model_result', ['wt.touchpoint_batch_id', 'tp.event_id', 'wt.person_id']) }} as attribution_model_result_id,
        wt.touchpoint_occurred_at,
        'last_marketing_touch' as attribution_model_name,
        wt.touchpoint_batch_id,
        wt.touchpoint_event_id,
        tp.event_id as attributed_event_id,
        wt.person_id,
        tp.event_occurred_at as attributed_event_occurred_at,
        -- Marketing attribution fields from the last touchpoint
        wt.source,
        wt.medium,
        wt.campaign,
        wt.content,
        wt.gclid
    from web_touchpoints wt
    inner join touchpoint_paths tp
        on wt.touchpoint_batch_id = tp.touchpoint_batch_id
        and wt.person_id = tp.person_id
)

select * from final_output
order by person_id, touchpoint_occurred_at, attributed_event_id

