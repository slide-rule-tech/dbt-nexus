{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized']
) }}

-- Normalized thread participants: Aggregate participants by thread
-- Shows all participants in each thread with their roles and participation stats
WITH messages AS (
    SELECT * FROM {{ ref('gmail_messages') }}
),

participants AS (
    SELECT * FROM {{ ref('gmail_message_participants') }}
),

-- Join participants with messages to get thread_id
participants_with_threads AS (
    SELECT 
        p.message_id,
        p.participant_raw,
        p.name,
        p.email,
        p.domain,
        p.role,
        p.sent_at,
        p._ingested_at,
        m.thread_id
    FROM participants p
    INNER JOIN messages m ON p.message_id = m.message_id
    WHERE m.thread_id IS NOT NULL
),

-- Aggregate participants by thread and email
thread_participants AS (
    SELECT
        thread_id,
        email,
        
        -- Participant info (use most common name, or first if tie)
        ARRAY_AGG(name ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as name,
        ARRAY_AGG(participant_raw ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as participant_raw,
        domain,
        
        -- Roles this participant has had in the thread (collect all, deduplicate later)
        ARRAY_AGG(role) as roles_raw,
        
        -- Participation stats
        COUNT(DISTINCT message_id) as message_count,
        MIN(sent_at) as first_participated_at,
        MAX(sent_at) as last_participated_at,
        MIN(_ingested_at) as first_ingested_at,
        MAX(_ingested_at) as last_ingested_at,
        
        -- Count by role
        COUNTIF(role = 'sender') as sender_count,
        COUNTIF(role = 'recipient') as recipient_count,
        COUNTIF(role = 'cced') as cced_count,
        COUNTIF(role = 'bcced') as bcced_count
    FROM participants_with_threads
    WHERE email IS NOT NULL
    GROUP BY thread_id, email, domain
)

SELECT 
    thread_id,
    email,
    name,
    participant_raw,
    domain,
    -- Deduplicate and sort roles
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
    ) as roles,
    message_count,
    first_participated_at,
    last_participated_at,
    first_ingested_at,
    last_ingested_at,
    sender_count,
    recipient_count,
    cced_count,
    bcced_count
FROM thread_participants
ORDER BY thread_id, 
    -- Helper for ordering: primary role (lowest priority number)
    CASE 
        WHEN 'sender' IN (SELECT role FROM UNNEST(roles_raw) as role) THEN 1
        WHEN 'recipient' IN (SELECT role FROM UNNEST(roles_raw) as role) THEN 2
        WHEN 'cced' IN (SELECT role FROM UNNEST(roles_raw) as role) THEN 3
        WHEN 'bcced' IN (SELECT role FROM UNNEST(roles_raw) as role) THEN 4
        ELSE 5
    END,
    first_participated_at ASC,
    email

