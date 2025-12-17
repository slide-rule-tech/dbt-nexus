{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'person_identifiers']
) }}

-- Extract person identifiers from gmail thread participants
WITH participants AS (
    SELECT * FROM {{ ref('gmail_thread_participants') }}
),

participants_with_event_id AS (
    SELECT 
        {{ nexus.create_nexus_id('event', ['thread_id', "'thread started'"]) }} as event_id,
        thread_id,
        email,
        first_participated_at,
        _ingested_at,
        roles
    FROM participants
    WHERE email IS NOT NULL
),

-- Unnest roles to create one identifier per role
participants_with_roles AS (
    SELECT 
        event_id,
        thread_id,
        email,
        first_participated_at,
        _ingested_at,
        role
    FROM participants_with_event_id,
    UNNEST(roles) as role
),

identifiers AS (
    SELECT 
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'email', "'person'", 'role']) }} as entity_identifier_id,
        event_id,
        {{ nexus.create_nexus_id('edge', ['event_id', 'email', "'person'", 'role']) }} as edge_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'gmail' as source,
        first_participated_at as occurred_at,
        _ingested_at,
        role
    FROM participants_with_roles
),

-- Deduplicate: same entity_identifier_id can appear from multiple streams/ingestions
-- Keep the row with the most recent _ingested_at
deduplicated_identifiers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY entity_identifier_id 
            ORDER BY _ingested_at DESC
        ) as rn
    FROM identifiers
)

SELECT 
    entity_identifier_id,
    event_id,
    edge_id,
    entity_type,
    identifier_type,
    identifier_value,
    source,
    occurred_at,
    _ingested_at,
    role
FROM deduplicated_identifiers
WHERE rn = 1
ORDER BY occurred_at DESC

