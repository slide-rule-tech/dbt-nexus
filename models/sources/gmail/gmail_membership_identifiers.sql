{{ config(enabled=var('nexus', {}).get('gmail', {}).get('enabled', false), materialized='table',tags=['identity-resolution', 'event-processing', 'memberships', 'realtime']) }}

-- Create memberships for senders (using pre-computed domain, excluding generic domains)
WITH sender_memberships AS (
    SELECT 
        {{ create_nexus_id('membership_identifier', ['event_id', 'sender.email', 'sender.domain', 'occurred_at', "'sender'"]) }} as membership_identifier_id,
        event_id,
        sender.email as person_identifier,
        'email' as person_identifier_type,
        sender.domain as group_identifier,
        'domain' as group_identifier_type,
        null as role,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }}
    WHERE sender.email IS NOT NULL
    AND sender.domain IS NOT NULL
    AND NOT sender.generic_domain
),

recipient_memberships AS (
    SELECT 
        {{ create_nexus_id('membership_identifier', ['event_id', 'recipient.email', 'recipient.domain', 'occurred_at', "'recipient'"]) }} as membership_identifier_id,
        event_id,
        recipient.email as person_identifier,
        'email' as person_identifier_type,
        recipient.domain as group_identifier,
        'domain' as group_identifier_type,
        null as role,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }},
    UNNEST(recipients) as recipient
    WHERE recipient.email IS NOT NULL
    AND recipient.domain IS NOT NULL
    AND NOT recipient.generic_domain
),

unioned AS (
    SELECT * FROM sender_memberships
    UNION ALL
    SELECT * FROM recipient_memberships
)

SELECT 
    membership_identifier_id,
    event_id,
    person_identifier,
    person_identifier_type,
    group_identifier,
    group_identifier_type,
    role,
    source,
    occurred_at
FROM unioned
ORDER BY event_id DESC 