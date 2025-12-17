{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized', 'by_account']
) }}

-- Per-account normalized thread participants: Aggregate participants by gmail_thread_id
WITH messages AS (
    SELECT * FROM {{ ref('gmail_messages_by_account') }}
),

participants AS (
    SELECT * FROM {{ ref('gmail_message_participants_by_account') }}
),

participants_with_threads AS (
    SELECT 
        p.gmail_message_id,
        p.email,
        p.name,
        p.participant_raw,
        p.domain,
        p.role,
        p.sent_at,
        p._ingested_at,
        p._account,
        m.gmail_thread_id
    FROM participants p
    INNER JOIN messages m 
        ON p.gmail_message_id = m.gmail_message_id 
        AND p._account = m._account
    WHERE m.gmail_thread_id IS NOT NULL
      AND p.email IS NOT NULL
),

thread_participants AS (
    SELECT
        gmail_thread_id,
        _account,
        email,
        ARRAY_AGG(name ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as name,
        ARRAY_AGG(participant_raw ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as participant_raw,
        domain,
        ARRAY_AGG(role) as roles_raw,
        MIN(sent_at) as first_participated_at,
        MAX(sent_at) as last_participated_at,
        MIN(_ingested_at) as _ingested_at,
    FROM participants_with_threads
    GROUP BY gmail_thread_id, _account, email, domain
),

final as (
SELECT 
    gmail_thread_id,
    _account,
    email,
    name,
    participant_raw,
    domain,
    ARRAY(
        SELECT DISTINCT role 
        FROM UNNEST(roles_raw) as role
        ORDER BY 
            CASE role 
                WHEN 'sender' THEN 1
                WHEN 'recipient' THEN 2
                WHEN 'cced' THEN 3
                WHEN 'bcced' THEN 4
            END
    ) as     roles,
    first_participated_at,
    last_participated_at,
    _ingested_at
FROM thread_participants
ORDER BY gmail_thread_id, 
    CASE 
        WHEN 'sender' IN (SELECT role FROM UNNEST(roles_raw) as role) THEN 1
        WHEN 'recipient' IN (SELECT role FROM UNNEST(roles_raw) as role) THEN 2
        WHEN 'cced' IN (SELECT role FROM UNNEST(roles_raw) as role) THEN 3
        WHEN 'bcced' IN (SELECT role FROM UNNEST(roles_raw) as role) THEN 4
        ELSE 5
    END,
    first_participated_at ASC,
    email
)

select * from final
ORDER BY last_participated_at desc