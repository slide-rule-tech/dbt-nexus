-- Nexus formatted events for Segment identifies
-- Uses timestamp as the occurred_at timestamp
-- Follows nexus event schema pattern

{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'events'], 
    materialized='table'
) }}

{% set global_event_name_prefix = var('nexus', {}).get('sources', {}).get('segment', {}).get('event_name_prefix', none) %}
{% set source_prefix_cases = [] %}
{% for segment_source in var('segment_sources', []) %}
    {% if segment_source.get('event_name_prefix', none) is not none %}
        {% set escaped_prefix = segment_source.get('event_name_prefix') | replace("'", "''") %}
        {% set escaped_source = segment_source.get('name') | replace("'", "''") %}
        {% do source_prefix_cases.append("when segment_source = '" ~ escaped_source ~ "' then '" ~ escaped_prefix ~ "'") %}
    {% endif %}
{% endfor %}

with source_data as (
    select 
        *,
        case 
            when segment_call_model like '%identifies%' then 'identify'
            when segment_call_model like '%aliases%' then 'alias'
            when segment_call_model like '%tracks%' then 'track'
            when segment_call_model like '%screens%' then 'screen'
            when segment_call_model like '%groups%' then 'group'
            when segment_call_model like '%page%' then 'page'
        end as segment_event_type,
        case
            {% if source_prefix_cases | length > 0 %}
            {{ source_prefix_cases | join('\n            ') }}
            {% endif %}
            {% if global_event_name_prefix is not none %}
            else '{{ global_event_name_prefix | replace("'", "''") }}'
            {% else %}
            else null
            {% endif %}
        end as configured_event_name_prefix
    from {{ ref('cleaned_segment_all_columns') }}
),

formatted_events as (
    select
        {{ nexus.create_nexus_id('event', ['id', 'timestamp']) }} as event_id,
        timestamp as occurred_at,
        'web' as event_type,
        case
            when configured_event_name_prefix is not null then
                trim(configured_event_name_prefix) || ' ' ||
                case
                    when segment_event_type = 'identify' then 'user identified'
                    when segment_event_type = 'alias' then 'user aliased'
                    when segment_event_type = 'track' then lower(event_text)
                    when segment_event_type = 'screen' then 'screen viewed'
                    when segment_event_type = 'group' then 'user grouped'
                    when segment_event_type = 'page' then 'page viewed'
                end
            else
                case
                    when segment_event_type = 'identify' then 'user identified'
                    when segment_event_type = 'alias' then 'user aliased'
                    when segment_event_type = 'track' then lower(event_text)
                    when segment_event_type = 'screen' then 'screen viewed'
                    when segment_event_type = 'group' then 'user grouped'
                    when segment_event_type = 'page' then 'page viewed'
                end
        end as event_name,
        'segment' as source,

        -- Optional fields
        case
            when segment_event_type = 'identify' then concat('User identified: ', anonymous_id)
            when segment_event_type = 'alias' then 'User aliased'
            when segment_event_type = 'track' then concat('tracked ', lower(event_text))
            when segment_event_type = 'screen' then concat('viewed ', context_page_title, ' screen')
            when segment_event_type = 'group' then 'User grouped'
            when segment_event_type = 'page' then concat('viewed ', context_page_title, ' page')
        end as event_description,
        0 as significance,
        current_timestamp() as _ingested_at,

        anonymous_id as segment_anonymous_id,
        id as segment_id,
        context_page_title as page_title,
        context_page_referrer as page_referrer,
        context_page_url as page_url,
        {{ dbt_utils.star(ref('cleaned_segment_all_columns'), except=['anonymous_id', 'id', 'context_page_title', 'context_page_referrer', 'context_page_url', 'page_title', 'page_referrer', 'page_url']) }}
        

    from source_data
    where timestamp is not null
      and timestamp > '1900-01-01'  -- Filter out invalid dates
)

select 
    *
from formatted_events
order by occurred_at desc
