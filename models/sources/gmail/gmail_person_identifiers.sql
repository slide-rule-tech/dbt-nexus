{{ config(
    enabled=var('nexus', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['identity-resolution', 'event-processing', 'persons', 'realtime']
) }}

WITH sender_identifiers AS (
    SELECT 
        {{ create_nexus_id('person_identifier', ['event_id', 'sender.email']) }} as identifier_id,
        event_id,
        {{ create_nexus_id('person_edge', ['event_id', 'sender.email']) }} as edge_id,
        'email' as identifier_type,
        sender.email as identifier_value,
        'sender' as role,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }}
    WHERE sender.email IS NOT NULL
),

recipient_identifiers AS (
    SELECT 
        {{ create_nexus_id('person_identifier', ['event_id', 'recipient.email']) }} as identifier_id,
        event_id,
        {{ create_nexus_id('person_edge', ['event_id', 'recipient.email']) }} as edge_id,
        'email' as identifier_type,
        recipient.email as identifier_value,
        'recipient' as role,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }},
    UNNEST(recipients) as recipient
    WHERE recipient.email IS NOT NULL
),

unioned AS (
    SELECT * FROM sender_identifiers
    UNION ALL
    SELECT * FROM recipient_identifiers
)

SELECT 
    identifier_id,
    event_id,
    edge_id,
    identifier_type,
    identifier_value,
    role,
    occurred_at,
    source
FROM unioned
ORDER BY event_id DESC
