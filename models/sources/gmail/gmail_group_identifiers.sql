{{ config(
    enabled=var('nexus', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['identity-resolution', 'event-processing', 'groups', 'realtime']
) }}

-- Extract domains from sender emails (using pre-computed domain, excluding generic domains)
WITH sender_domains AS (
    SELECT 
        event_id,
        occurred_at,
        sender.domain as domain,
        'sender_domain' as role
    FROM {{ ref('gmail_messages_base') }}
    WHERE sender.domain IS NOT NULL
    AND NOT sender.generic_domain
),

-- Extract domains from recipient emails (using pre-computed domain, excluding generic domains)
recipient_domains AS (
    SELECT 
        event_id,
        occurred_at,
        recipient.domain as domain,
        'recipient_domain' as role
    FROM {{ ref('gmail_messages_base') }},
    UNNEST(recipients) as recipient
    WHERE recipient.domain IS NOT NULL
    AND NOT recipient.generic_domain
),

-- Union all domains
all_domains AS (
    SELECT * FROM sender_domains
    UNION DISTINCT
    SELECT * FROM recipient_domains
),

-- Create domain identifiers (generic domains already filtered upstream)
filtered_domains AS (
    SELECT 
        event_id,
        {{ dbt_utils.generate_surrogate_key(['event_id', 'domain']) }} as edge_id,
        'domain' as identifier_type,
        domain as identifier_value,
        role,
        occurred_at,
        'gmail' as source
    FROM all_domains
    WHERE domain IS NOT NULL
    AND domain NOT LIKE '%>%'
),

-- Add redirected domains (www. versions of email domains)
redirected_domains AS (
    SELECT 
        event_id,
        {{ dbt_utils.generate_surrogate_key(['event_id', redirected_domain('domain')]) }} as edge_id,
        'domain' as identifier_type,
        {{ redirected_domain('domain') }} as identifier_value,
        role,
        occurred_at,
        'gmail' as source
    FROM all_domains
    WHERE domain IS NOT NULL
    AND domain NOT LIKE '%>%'
),

unioned AS (
    SELECT * FROM filtered_domains
    UNION ALL
    SELECT * FROM redirected_domains
)

SELECT 
    event_id,
    edge_id,
    identifier_type,
    identifier_value,
    role,
    occurred_at,
    source
FROM unioned
ORDER BY event_id DESC 