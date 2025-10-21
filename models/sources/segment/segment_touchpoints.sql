-- Nexus Touchpoints - Segment Attribution Events
-- Filters segment_events for events with attribution information (UTM parameters, fbclid, etc.)
-- Follows the attribution modeling schema from exploration.md

{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false),
    tags=['attribution', 'touchpoints'], 
    materialized='table'
) }}

with segment_events as (
    select * from {{ ref('segment_events') }}
),

touchpoint_events as (
    select
        -- Touchpoint identification
        {{ nexus.create_nexus_id('touchpoint', ['event_id', 'occurred_at']) }} as touchpoint_id,
        event_id,
        event_name,
        event_type,
        occurred_at,
        
        -- Attribution fields from UTM parameters (preferred source)
        context_campaign_source as source,
        context_campaign_medium as medium,
        context_campaign_name as campaign,
        context_campaign_content as content,
        context_campaign_term as term,
        
        -- Channel classification
        case 
            when context_campaign_source is not null then 'paid'
            when context_page_referrer like '%facebook%' or context_page_search like '%fbclid%' then 'social'
            when context_page_referrer like '%google%' then 'organic'
            when context_page_referrer is not null 
                 {% for exclusion in var('referral_exclusions') -%}
                 and context_page_referrer not like '{{ exclusion }}'
                 {% endfor -%}
                 then 'referral'
            else 'direct'
        end as channel,
        
        -- Touchpoint type
        case 
            when context_campaign_source is not null then 'campaign'
            when context_page_search like '%fbclid%' then 'facebook_click'
            when context_page_referrer is not null 
                 {% for exclusion in var('referral_exclusions') -%}
                 and context_page_referrer not like '{{ exclusion }}'
                 {% endfor -%}
                 then 'referral'
            else 'direct'
        end as touchpoint_type,
        
        -- Landing page information
        context_page_path as landing_page,
        context_page_referrer as referrer,
        context_page_url as landing_url,
        
        -- Click IDs
        case 
            when context_page_search like '%fbclid=%' then 
                regexp_substr(context_page_search, 'fbclid=([^&]+)', 1, 1, 'e')
            else null
        end as fbclid,
        
        case 
            when context_page_search like '%gclid=%' then 
                regexp_substr(context_page_search, 'gclid=([^&]+)', 1, 1, 'e')
            else null
        end as gclid,
        
        case 
            when context_page_search like '%ttclid=%' then 
                regexp_substr(context_page_search, 'ttclid=([^&]+)', 1, 1, 'e')
            else null
        end as ttclid,
        
        case 
            when context_page_search like '%li_fat_id=%' then 
                regexp_substr(context_page_search, 'li_fat_id=([^&]+)', 1, 1, 'e')
            else null
        end as li_fat_id,
        

    from segment_events
    
    -- Filter for events that have attribution information
    where (
        -- UTM parameters present
        context_campaign_source is not null
        or context_campaign_medium is not null
        or context_campaign_name is not null
        
        -- Click IDs present
        or context_page_search like '%fbclid=%'
        or context_page_search like '%gclid=%'
        or context_page_search like '%ttclid=%'
        or context_page_search like '%li_fat_id=%'
        
        -- Referrer present (for referral attribution) - exclude internal referrers
        or (context_page_referrer is not null 
            {% for exclusion in var('referral_exclusions') -%}
            and context_page_referrer not like '{{ exclusion }}'
            {% endfor -%}
            )
    )
),

final as (
    select
        touchpoint_id,
        event_id as touchpoint_event_id,
        event_name,
        event_type,
        occurred_at,
        
        -- Standardized attribution fields
        source,
        medium,
        campaign,
        content,
        term,
        
        -- Channel and type classification
        channel,
        touchpoint_type,
        
        -- Landing page details
        landing_page,
        referrer,
        landing_url,
        
        -- Click tracking IDs
        fbclid,
        gclid,
        ttclid,
        li_fat_id,
        

        {{ nexus.create_nexus_id('attribution_deduplication_key', ['source', 'medium', 'campaign', 'content', 'term', 'referrer',  'fbclid', 'gclid', 'ttclid', 'li_fat_id']) }} as attribution_deduplication_key,
        
    
    from touchpoint_events
)

select * from final
order by occurred_at desc
