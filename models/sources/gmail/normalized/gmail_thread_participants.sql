{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized']
) }}

-- Cross-account normalized thread participants: Group per-account participants by first_message_id_header
WITH per_account_participants AS (
    SELECT * FROM {{ ref('gmail_thread_participants_by_account') }}
),

per_account_threads AS (
    SELECT * FROM {{ ref('gmail_threads_by_account') }}
),

participants_with_thread_id AS (
    SELECT 
        pat.first_message_id_header as thread_id,
        pap.email,
        pap.name,
        pap.participant_raw,
        pap.domain,
        pap.roles,
        pap.first_participated_at,
        pap.last_participated_at,
        pap._ingested_at
    FROM per_account_participants pap
    INNER JOIN per_account_threads pat
        ON pap.gmail_thread_id = pat.gmail_thread_id
        AND pap._account = pat._account
    WHERE pat.first_message_id_header IS NOT NULL
),

thread_participants AS (
    SELECT
        thread_id,
        email,
        ARRAY_AGG(name ORDER BY first_participated_at ASC LIMIT 1)[OFFSET(0)] as name,
        ARRAY_AGG(participant_raw ORDER BY first_participated_at ASC LIMIT 1)[OFFSET(0)] as participant_raw,
        domain,
        ARRAY_CONCAT_AGG(roles) as roles_raw,
        MIN(first_participated_at) as first_participated_at,
        MAX(last_participated_at) as last_participated_at,
        MIN(_ingested_at) as _ingested_at
    FROM participants_with_thread_id
    GROUP BY thread_id, email, domain
),

final as (

SELECT 
    thread_id,
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
    ) as roles,
    first_participated_at,
    last_participated_at,
    _ingested_at
FROM thread_participants
ORDER BY thread_id, 
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