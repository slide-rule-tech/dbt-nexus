{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'group_identifiers']
) }}

-- Extract group (domain) identifiers from google calendar event participants
WITH participants AS (
    SELECT * FROM {{ ref('google_calendar_event_participants') }}
),

-- Filter out generic domains
domains_filtered AS (
    SELECT DISTINCT
        {{ nexus.create_nexus_id('event', ['calendar_event_id', 'start_time']) }} as event_id,
        start_time,
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
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'domain', "'group'", 'role', 'start_time']) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        domain as identifier_value,
        'google_calendar' as source,
        start_time as occurred_at,
        _ingested_at,
        role
    FROM domains_filtered
    WHERE domain IS NOT NULL
),

-- Add redirected domains (www. versions)
redirected_domains AS (
    SELECT
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', nexus.redirected_domain('domain'), "'group'", 'role', 'start_time']) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        {{ nexus.redirected_domain('domain') }} as identifier_value,
        'google_calendar' as source,
        start_time as occurred_at,
        _ingested_at,
        role
    FROM domains_filtered
    WHERE domain IS NOT NULL
)

SELECT * FROM domain_identifiers
UNION ALL
SELECT * FROM redirected_domains
ORDER BY occurred_at DESC
