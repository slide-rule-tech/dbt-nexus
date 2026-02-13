-- Nexus Touchpoints - Segment Attribution Events
-- Includes both attributed touchpoints (UTM, referrer, click IDs) and direct first-visit touchpoints
-- Follows the attribution modeling schema from exploration.md

{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false),
    tags=['attribution', 'touchpoints'], 
    materialized='table'
) }}

with segment_events as (
    select * from {{ ref('segment_events') }}
),

-- ============================================
-- ATTRIBUTED TOUCHPOINTS (UTM, referrer, click IDs)
-- ============================================
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
            when page_referrer like '%facebook%' or context_page_search like '%fbclid%' then 'social'
            when page_referrer like '%google%' then 'organic'
            when page_referrer is not null 
                 {% for exclusion in var('referral_exclusions') -%}
                 and page_referrer not like '{{ exclusion }}'
                 {% endfor -%}
                 then 'referral'
            else 'direct'
        end as channel,
        
      
        -- Landing page information
        context_page_path as landing_page,
        page_referrer as referrer,
        page_url as landing_url,
        
        -- Click IDs - Cross-database compatible regex extraction
        {% if target.type == 'bigquery' %}
        case 
            when context_page_search like '%fbclid=%' then 
                REGEXP_EXTRACT(context_page_search, r'fbclid=([^&]+)')
            else null
        end as fbclid,
        
        case 
            when context_page_search like '%gclid=%' then 
                REGEXP_EXTRACT(context_page_search, r'gclid=([^&]+)')
            else null
        end as gclid,
        
        case 
            when context_page_search like '%ttclid=%' then 
                REGEXP_EXTRACT(context_page_search, r'ttclid=([^&]+)')
            else null
        end as ttclid,
        
        case 
            when context_page_search like '%li_fat_id=%' then 
                REGEXP_EXTRACT(context_page_search, r'li_fat_id=([^&]+)')
            else null
        end as li_fat_id
        {% else %}
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
        end as li_fat_id
        {% endif %}

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
        or (page_referrer is not null 
            {% for exclusion in var('referral_exclusions') -%}
            and page_referrer not like '{{ exclusion }}'
            {% endfor -%}
            )
    )
),

attributed_touchpoints as (
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
        
        -- Landing page details
        landing_page,
        referrer,
        landing_url,
        
        -- Click tracking IDs
        fbclid,
        gclid,
        ttclid,
        li_fat_id,

        {{ nexus.create_nexus_id('attribution_deduplication_key', ['source', 'medium', 'campaign', 'content', 'term', 'referrer', 'fbclid', 'gclid', 'ttclid', 'li_fat_id']) }} as attribution_deduplication_key,
        'web' as touchpoint_type
    
    from touchpoint_events
),

-- ============================================
-- DIRECT TOUCHPOINTS (first visit without attribution)
-- ============================================

-- Find the first page view per anonymous_id
first_visits as (
    select
        segment_anonymous_id,
        MIN(occurred_at) as first_visit_at
    from segment_events
    where event_type = 'web'
      and segment_anonymous_id is not null
    group by 1
),

-- Get the full event data for first visits
first_visit_events as (
    select 
        se.*
    from segment_events se
    inner join first_visits fv 
        on se.segment_anonymous_id = fv.segment_anonymous_id 
        and se.occurred_at = fv.first_visit_at
),

-- Create direct touchpoints from first visits that don't have attribution data
direct_touchpoint_events as (
    select
        -- Touchpoint identification
        {{ nexus.create_nexus_id('touchpoint', ['event_id', 'occurred_at']) }} as touchpoint_id,
        event_id as touchpoint_event_id,
        event_name,
        event_type,
        occurred_at,
        
        -- No attribution data - all null
        cast(null as string) as source,
        cast(null as string) as medium,
        cast(null as string) as campaign,
        cast(null as string) as content,
        cast(null as string) as term,
        
        -- Channel is explicitly 'direct'
        'direct' as channel,
        
        -- Landing page details
        context_page_path as landing_page,
        cast(null as string) as referrer,
        page_url as landing_url,
        
        -- No click IDs
        cast(null as string) as fbclid,
        cast(null as string) as gclid,
        cast(null as string) as ttclid,
        cast(null as string) as li_fat_id,
        
        -- Deduplication key based on channel and landing page
        {{ nexus.create_nexus_id('attribution_deduplication_key', ["'direct'", 'context_page_path']) }} as attribution_deduplication_key,
        'web' as touchpoint_type
        
    from first_visit_events
    
    -- Exclude events that already qualify as attributed touchpoints
    where (context_campaign_source is null or context_campaign_source = '')
      and (context_campaign_medium is null or context_campaign_medium = '')
      and (context_campaign_name is null or context_campaign_name = '')
      and (context_page_search is null or context_page_search not like '%fbclid=%')
      and (context_page_search is null or context_page_search not like '%gclid=%')
      and (context_page_search is null or context_page_search not like '%ttclid=%')
      and (context_page_search is null or context_page_search not like '%li_fat_id=%')
      and (
          page_referrer is null 
          or page_referrer = ''
          {% for exclusion in var('referral_exclusions') -%}
          or page_referrer like '{{ exclusion }}'
          {% endfor -%}
      )
),

-- ============================================
-- COMBINE ALL TOUCHPOINTS
-- ============================================
final as (
    select * from attributed_touchpoints
    union all
    select * from direct_touchpoint_events
)

select * from final
order by occurred_at desc
