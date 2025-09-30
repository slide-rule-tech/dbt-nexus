-- Nexus formatted events for Segment identifies
-- Uses timestamp as the occurred_at timestamp
-- Follows nexus event schema pattern

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'events'], 
    materialized='table'
) }}

with source_data as (
    select * from {{ ref('base_segment_all_calls') }}
),

formatted_events as (
    select
        {% set identifiers = var('nexus').segment.identifiers %}
        '{{ identifiers | join(",") }}' as test_field,
        -- Required nexus event fields
        {{ nexus.create_nexus_id('event', ['id', 'timestamp']) }} as event_id,
        timestamp as occurred_at,
        'identity' as event_type,
        'user identified' as event_name,
        'segment' as source,

        -- Optional fields
        'User identified in Segment' as event_description,
        null as value,
        null as value_unit,
        null as significance,
        current_timestamp() as _ingested_at,

        -- Source-specific fields (for reference)
        id as segment_id,
        anonymous_id as segment_anonymous_id,
        original_timestamp,
        timestamp,
        received_at,
        sent_at,
        uuid_ts,
        

        {%- set traits = var('nexus').segment.traits -%}
        {%- for trait in traits -%}
        {{ trait }}{%- if not loop.last -%},{%- endif -%}
        {%- endfor -%},
        
        
        -- Context fields
        context_campaign_content,
        context_campaign_name,
        context_campaign_medium,
        context_campaign_source,
        context_campaign_term,
        
        
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
