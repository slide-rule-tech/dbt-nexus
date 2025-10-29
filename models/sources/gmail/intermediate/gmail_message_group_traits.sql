{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'group_traits']
) }}

-- Extract group (domain) traits from gmail message participants
WITH participants AS (
    SELECT * FROM {{ ref('gmail_message_participants') }}
),

-- Filter out generic domains
domains_filtered AS (
    SELECT DISTINCT
        {{ nexus.create_nexus_id('event', ['message_id']) }} as event_id,
        sent_at,
        _ingested_at,
        domain
    FROM participants
    WHERE {{ filter_non_generic_domains('domain') }}
      AND domain NOT LIKE '%>%'
),

-- Create domain traits
domain_traits AS (
    -- Domain as a trait (for searchability)
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'domain', "'group'", "'domain'"]) }} as entity_trait_id,
        event_id,
        'group' as entity_type,
        'domain' as identifier_type,
        domain as identifier_value,
        'domain' as trait_name,
        domain as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    FROM domains_filtered
    WHERE domain IS NOT NULL
)

SELECT * FROM domain_traits
ORDER BY occurred_at DESC
