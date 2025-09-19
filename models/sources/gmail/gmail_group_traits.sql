{{ config(
    enabled=var('nexus', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['identity-resolution', 'event-processing', 'groups', 'realtime']
) }}

-- Extract unique domains from all emails (using pre-computed domain, excluding generic domains)
WITH all_domains AS (
    SELECT DISTINCT
        event_id,
        occurred_at,
        sender.domain as domain,
        sender.internal as internal
    FROM {{ ref('gmail_messages_base') }}
    WHERE sender.domain IS NOT NULL
    AND NOT sender.generic_domain
    
    UNION DISTINCT
    
    SELECT DISTINCT
        event_id,
        occurred_at,
        recipient.domain as domain,
        recipient.internal as internal
    FROM {{ ref('gmail_messages_base') }},
    UNNEST(recipients) as recipient
    WHERE recipient.domain IS NOT NULL
    AND NOT recipient.generic_domain
),

-- Create domain traits (generic domains already filtered upstream)
domain_traits AS (
    SELECT 
        event_id,
        'domain' as identifier_type,
        domain as identifier_value,
        'domain' as trait_name,
        domain as trait_value,
        'gmail' as source,
        occurred_at
    FROM all_domains
    WHERE domain IS NOT NULL
),



-- Add internal trait for domains
domain_internal_traits AS (
    SELECT 
        event_id,
        'domain' as identifier_type,
        domain as identifier_value,
        'internal' as trait_name,
        CAST(internal AS STRING) as trait_value,
        'gmail' as source,
        occurred_at
    FROM all_domains
    WHERE domain IS NOT NULL
),

-- Add redirected domain traits (www. versions)
redirected_domain_traits AS (
    SELECT 
        event_id,
        'domain' as identifier_type,
        {{ redirected_domain('domain') }} as identifier_value,
        'domain' as trait_name,
        {{ redirected_domain('domain') }} as trait_value,
        'gmail' as source,
        occurred_at
    FROM all_domains
    WHERE domain IS NOT NULL
),



-- Add internal trait for redirected domains
redirected_domain_internal_traits AS (
    SELECT 
        event_id,
        'domain' as identifier_type,
        {{ redirected_domain('domain') }} as identifier_value,
        'internal' as trait_name,
        CAST(internal AS STRING) as trait_value,
        'gmail' as source,
        occurred_at
    FROM all_domains
    WHERE domain IS NOT NULL
),

unioned AS (
    SELECT * FROM domain_traits
    UNION ALL
    SELECT * FROM domain_internal_traits
    UNION ALL
    SELECT * FROM redirected_domain_traits
    UNION ALL
    SELECT * FROM redirected_domain_internal_traits
)

SELECT 
    event_id,
    {{ dbt_utils.generate_surrogate_key(['event_id', 'identifier_value', 'trait_name']) }} as edge_id,
    identifier_type,
    identifier_value,
    trait_name,
    trait_value,
    occurred_at,
    source
FROM unioned
ORDER BY event_id DESC 