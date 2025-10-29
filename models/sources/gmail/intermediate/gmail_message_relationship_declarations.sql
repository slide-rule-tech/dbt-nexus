{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'relationship_declarations']
) }}

-- Extract person→group relationships from gmail message participants
WITH participants AS (
    SELECT * FROM {{ ref('gmail_message_participants') }}
),

-- Extract participants with valid email and domain (filter generic domains)
participants_with_domains AS (
    SELECT
        {{ nexus.create_nexus_id('event', ['message_id']) }} as event_id,
        sent_at,
        email as entity_a_identifier,
        domain as entity_b_identifier,
        role
    FROM participants
    WHERE email IS NOT NULL
      AND domain IS NOT NULL
      AND {{ filter_non_generic_domains('domain') }}
      AND domain NOT LIKE '%>%'
),

-- Create relationships
relationships AS (
    SELECT DISTINCT
        event_id,
        sent_at as occurred_at,
        entity_a_identifier,
        'email' as entity_a_identifier_type,
        'person' as entity_a_type,
        'member' as entity_a_role,
        entity_b_identifier,
        'domain' as entity_b_identifier_type,
        'group' as entity_b_type,
        'organization' as entity_b_role,
        'membership' as relationship_type,
        'a_to_b' as relationship_direction,
        true as is_active,
        'gmail' as source
    FROM participants_with_domains
)

SELECT
    {{ nexus.create_nexus_id('relationship_declaration', ['event_id', 'entity_a_identifier', 'entity_b_identifier', 'entity_a_role', 'occurred_at']) }} as relationship_declaration_id,
    event_id,
    occurred_at,
    entity_a_identifier,
    entity_a_identifier_type,
    entity_a_type,
    entity_a_role,
    entity_b_identifier,
    entity_b_identifier_type,
    entity_b_type,
    entity_b_role,
    relationship_type,
    relationship_direction,
    is_active,
    source
FROM relationships
ORDER BY occurred_at DESC
