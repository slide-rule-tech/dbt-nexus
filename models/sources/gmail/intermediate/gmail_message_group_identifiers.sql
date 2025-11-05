{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'group_identifiers']
) }}

-- Extract group (domain) identifiers from gmail message participants
WITH participants AS (
    SELECT * FROM {{ ref('gmail_message_participants') }}
),

-- Filter out generic domains
domains_filtered AS (
    SELECT DISTINCT
        {{ nexus.create_nexus_id('event', ['message_id']) }} as event_id,
        sent_at,
        _ingested_at,
        domain,
        role
    FROM participants
    WHERE {{ filter_non_generic_domains('domain') }}
      AND domain NOT LIKE '%>%'
),

-- Create domain identifiers
domain_identifiers AS (
    SELECT
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'domain', "'group'", 'role', 'sent_at']) }} as entity_identifier_id,
        event_id,
        {{ nexus.create_nexus_id('edge', ['event_id', 'domain', "'group'", 'role']) }} as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        domain as identifier_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at,
        role
    FROM domains_filtered
    WHERE domain IS NOT NULL
),

-- Add redirected domains (www. versions)
redirected_domains AS (
    SELECT
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', nexus.redirected_domain('domain'), "'group'", 'role', 'sent_at']) }} as entity_identifier_id,
        event_id,
        {{ nexus.create_nexus_id('edge', ['event_id', nexus.redirected_domain('domain'), "'group'", 'role']) }} as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        {{ nexus.redirected_domain('domain') }} as identifier_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at,
        role
    FROM domains_filtered
    WHERE domain IS NOT NULL
)

SELECT * FROM domain_identifiers
UNION ALL
SELECT * FROM redirected_domains
ORDER BY occurred_at DESC
