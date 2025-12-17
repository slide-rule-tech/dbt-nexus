{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized']
) }}

-- Cross-account normalized participants: Group per-account participants by message_id_header
WITH per_account_participants AS (
    SELECT
        p.participant_raw,
        p.name,
        p.email,
        p.domain,
        p.role,
        p.sent_at,
        p._ingested_at,
        m.message_id_header as message_id
    FROM {{ ref('gmail_message_participants_by_account') }} p
    INNER JOIN {{ ref('gmail_messages_by_account') }} m 
        ON p.gmail_message_id = m.gmail_message_id 
        AND p._account = m._account
    WHERE m.message_id_header IS NOT NULL
),

-- Cross-account deduplication: group by message_id_header, email, and role
-- Keep the most recent record for each participant
grouped_participants AS (
    SELECT 
        message_id,
        email,
        role,
        ARRAY_AGG(participant_raw ORDER BY sent_at DESC, _ingested_at DESC LIMIT 1)[OFFSET(0)] as participant_raw,
        ARRAY_AGG(name ORDER BY sent_at DESC, _ingested_at DESC LIMIT 1)[OFFSET(0)] as name,
        ARRAY_AGG(domain ORDER BY sent_at DESC, _ingested_at DESC LIMIT 1)[OFFSET(0)] as domain,
        MAX(sent_at) as sent_at,
        MAX(_ingested_at) as _ingested_at
    FROM per_account_participants
    WHERE message_id IS NOT NULL
    GROUP BY message_id, email, role
)

final as (
SELECT 
    message_id,
    participant_raw,
    name,
    email,
    domain,
    role,
    sent_at,
    _ingested_at
FROM grouped_participants
ORDER BY message_id, 
    CASE role 
        WHEN 'sender' THEN 1
        WHEN 'recipient' THEN 2
        WHEN 'cced' THEN 3
        WHEN 'bcced' THEN 4
    END,
    email
)

select * from final
ORDER BY sent_at desc