{{ config(
    enabled=var('nexus', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['identity-resolution', 'event-processing', 'persons', 'realtime']
) }}

WITH sender_email_traits AS (
    SELECT 
        {{ create_nexus_id('person_trait', ['event_id', 'sender.email', "'email'", "'sender'"]) }} as person_trait_id,
        event_id,
        'email' as identifier_type,
        sender.email as identifier_value,
        'email' as trait_name,
        sender.email as trait_value,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }}
    WHERE sender.email IS NOT NULL
),

sender_name_traits AS (
    SELECT 
        {{ create_nexus_id('person_trait', ['event_id', 'sender.email', "'name'", "'sender'"]) }} as person_trait_id,
        event_id,
        'email' as identifier_type,
        sender.email as identifier_value,
        'name' as trait_name,
        sender.name as trait_value,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }}
    WHERE sender.email IS NOT NULL
    AND sender.name IS NOT NULL
    AND sender.name != ''
),

recipient_email_traits AS (
    SELECT 
        {{ create_nexus_id('person_trait', ['event_id', 'recipient.email', "'email'", "'recipient'"]) }} as person_trait_id,
        event_id,
        'email' as identifier_type,
        recipient.email as identifier_value,
        'email' as trait_name,
        recipient.email as trait_value,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }},
    UNNEST(recipients) as recipient
    WHERE recipient.email IS NOT NULL
),

recipient_name_traits AS (
    SELECT 
        {{ create_nexus_id('person_trait', ['event_id', 'recipient.email', "'name'", "'recipient'"]) }} as person_trait_id,
        event_id,
        'email' as identifier_type,
        recipient.email as identifier_value,
        'name' as trait_name,
        recipient.name as trait_value,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }},
    UNNEST(recipients) as recipient
    WHERE recipient.email IS NOT NULL
    AND recipient.name IS NOT NULL
    AND recipient.name != ''
),

-- Internal traits for senders
sender_internal_traits AS (
    SELECT 
        {{ create_nexus_id('person_trait', ['event_id', 'sender.email', "'internal'", "'sender'"]) }} as person_trait_id,
        event_id,
        'email' as identifier_type,
        sender.email as identifier_value,
        'internal' as trait_name,
        CAST(sender.internal AS STRING) as trait_value,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }}
    WHERE sender.email IS NOT NULL
),

-- Test traits for senders
sender_test_traits AS (
    SELECT 
        {{ create_nexus_id('person_trait', ['event_id', 'sender.email', "'test'", "'sender'"]) }} as person_trait_id,
        event_id,
        'email' as identifier_type,
        sender.email as identifier_value,
        'test' as trait_name,
        CAST(sender.test AS STRING) as trait_value,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }}
    WHERE sender.email IS NOT NULL
),

-- Internal traits for recipients
recipient_internal_traits AS (
    SELECT 
        {{ create_nexus_id('person_trait', ['event_id', 'recipient.email', "'internal'", "'recipient'"]) }} as person_trait_id,
        event_id,
        'email' as identifier_type,
        recipient.email as identifier_value,
        'internal' as trait_name,
        CAST(recipient.internal AS STRING) as trait_value,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }},
    UNNEST(recipients) as recipient
    WHERE recipient.email IS NOT NULL
),

-- Test traits for recipients
recipient_test_traits AS (
    SELECT 
        {{ create_nexus_id('person_trait', ['event_id', 'recipient.email', "'test'", "'recipient'"]) }} as person_trait_id,
        event_id,
        'email' as identifier_type,
        recipient.email as identifier_value,
        'test' as trait_name,
        CAST(recipient.test AS STRING) as trait_value,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }},
    UNNEST(recipients) as recipient
    WHERE recipient.email IS NOT NULL
),

unioned AS (
    SELECT * FROM sender_email_traits
    UNION ALL
    SELECT * FROM sender_name_traits
    UNION ALL
    SELECT * FROM recipient_email_traits
    UNION ALL
    SELECT * FROM recipient_name_traits
    UNION ALL
    SELECT * FROM sender_internal_traits
    UNION ALL
    SELECT * FROM sender_test_traits
    UNION ALL
    SELECT * FROM recipient_internal_traits
    UNION ALL
    SELECT * FROM recipient_test_traits
)

SELECT 
    person_trait_id,
    event_id,
    {{ create_nexus_id('person_edge', ['event_id', 'identifier_value', 'trait_name']) }} as edge_id,
    identifier_type,
    identifier_value,
    trait_name,
    trait_value,
    occurred_at,
    source
FROM unioned
ORDER BY event_id DESC 