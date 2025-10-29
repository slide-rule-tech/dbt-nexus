{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'group_traits']
) }}

-- Extract group (domain) traits from google calendar event participants
WITH participants AS (
    SELECT * FROM {{ ref('google_calendar_event_participants') }}
),

participants_with_nexus_event_id AS (
    SELECT
        {{ nexus.create_nexus_id('event', ['event_id']) }} as nexus_event_id,
        event_id,
        start_time,
        _ingested_at,
        domain
    FROM participants
),

-- Filter out generic domains
domains_filtered AS (
    SELECT DISTINCT
        nexus_event_id,
        event_id,
        start_time,
        _ingested_at,
        domain
    FROM participants_with_nexus_event_id
    WHERE {{ filter_non_generic_domains('domain') }}
      AND domain NOT LIKE '%>%'
),

-- Create domain traits
domain_traits AS (
    -- Domain as a trait (for searchability)
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['nexus_event_id', 'domain', "'group'", "'domain'"]) }} as entity_trait_id,
        nexus_event_id as event_id,
        'group' as entity_type,
        'domain' as identifier_type,
        domain as identifier_value,
        'domain' as trait_name,
        domain as trait_value,
        'google_calendar' as source,
        start_time as occurred_at,
        _ingested_at
    FROM domains_filtered
    WHERE domain IS NOT NULL
)

SELECT * FROM domain_traits
ORDER BY occurred_at DESC
