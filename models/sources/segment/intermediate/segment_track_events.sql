-- Nexus formatted events for Segment tracks
-- Uses timestamp as the occurred_at timestamp
-- Follows nexus event schema pattern

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'events'], 
    materialized='table'
) }}

with source_data as (
    select * from {{ ref('base_segment_tracks') }}
),

formatted_events as (
    select
        -- Required nexus event fields
        {{ nexus.create_nexus_id('event', ['id', 'timestamp']) }} as event_id,
        timestamp as occurred_at,
        'web' as event_type,
        lower(event_text) as event_name,
        'segment' as source,

        -- Optional fields
        coalesce(event_text || ' at ' || context_page_path, 'Segment track event') as event_description,
        null as value,
        null as value_unit,
        null as significance,
        current_timestamp() as _ingested_at,

        -- Source-specific fields (for reference)
        id as segment_id,
        event as segment_event,
        event_text as segment_event_text,
        user_id,
        anonymous_id as segment_anonymous_id,
        original_timestamp,
        timestamp,
        received_at,
        sent_at,
        uuid_ts,
        
        -- Context fields
        context_traits_name,
        context_traits_email,
        context_campaign_content,
        context_campaign_name,
        context_campaign_medium,
        context_campaign_source,
        context_campaign_term,
        context_campaign_id,
        context_campaign_ad_group,
        context_campaign_ad,
        context_campaign_funnel,
        context_campaign_platform,
        context_campaign_audience,
        context_campaign_marketing_audience,
        context_campaign_customer,
        context_campaign_source_platform,
        context_campaign_subid5,
        context_ip,
        context_timezone,
        context_locale,
        context_library_name,
        context_library_version,
        context_user_agent,
        context_user_agent_data_brands,
        context_user_agent_data_platform,
        context_user_agent_data_mobile,
        
        -- Page context fields
        context_page_search,
        context_page_path,
        context_page_url,
        context_page_referrer,
        context_page_title

    from source_data
    where timestamp is not null
      and timestamp > '1900-01-01'  -- Filter out invalid dates
)

select * from formatted_events
order by occurred_at desc