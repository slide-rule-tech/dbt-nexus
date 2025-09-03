{{ config(materialized='table',tags=['identity-resolution', 'event-processing', 'persons']) }}

WITH sender_identifiers AS (
    SELECT 
        event_id,
        {{ dbt_utils.generate_surrogate_key(['event_id', 'sender.email']) }} as row_id,
        'email' as identifier_type,
        sender.email as identifier_value,
        'gmail' as source,
        occurred_at
    FROM {{ ref('gmail_messages_base') }}
    WHERE sender.email IS NOT NULL
),

recipient_identifiers AS (
    SELECT 
        event_id,
        {{ dbt_utils.generate_surrogate_key(['event_id', 'recipient.email']) }} as row_id,
        'email' as identifier_type,
        recipient.email as identifier_value,
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
    event_id,
    row_id,
    identifier_type,
    identifier_value,
    occurred_at,
    source
FROM unioned
ORDER BY event_id DESC 