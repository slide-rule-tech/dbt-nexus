{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized']
) }}

-- Normalized layer: Clean, deduplicated messages with explicit columns
-- Extracts data from new STANDARD_TABLE_SCHEMA with _raw_record and headers array
WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') as message_id,
        _ingested_at,
        _connection_id,
        _stream_id,
        _sync_id,
        _account,
        _sync_metadata,
        _raw_record
    FROM {{ ref('gmail_messages_base_dedupped') }}
),

-- Extract headers for message-level data only
headers_extracted AS (
    SELECT
        *,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'message-id'
         LIMIT 1) as message_id_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'subject'
         LIMIT 1) as subject_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'in-reply-to'
         LIMIT 1) as in_reply_to_header
    FROM source_data
),

-- Final cleaned message with subject, threads, etc.
cleaned_message AS (
    SELECT
        -- Message identifiers
        message_id,
        JSON_EXTRACT_SCALAR(_raw_record, '$.threadId') as gmail_thread_id,
        JSON_EXTRACT_SCALAR(_raw_record, '$.historyId') as gmail_history_id,
        message_id_header,
        in_reply_to_header as in_reply_to,
        
        -- Timestamps
        TIMESTAMP_MILLIS(CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.internalDate') AS INT64)) as sent_at,
        
        
        -- Subject: clean common prefixes (RE:, FWD:, etc.) and keep original
        subject_header as raw_subject,
        -- Remove common email prefixes (RE:, Re:, re:, FWD:, Fwd:, fwd:, FW:, Fw:, etc.)
        -- Handle multiple prefixes by applying regex in a loop-like fashion
        TRIM(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(subject_header, ''),
                            r'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*',
                            ''
                        ),
                        r'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*',
                        ''
                    ),
                    r'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*',
                    ''
                ),
                r'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*',
                ''
            )
        ) as subject,
        
        -- Sync metadata
        _ingested_at,
        _raw_record as raw_record,
        _connection_id,
        _stream_id,
        _sync_id,
        _account,
        _sync_metadata,
        'gmail' as source
    FROM headers_extracted
    WHERE message_id IS NOT NULL
),

deduped_messages AS (
    SELECT 
        message_id_header as message_id,
        gmail_thread_id,
        gmail_history_id,
        message_id as gmail_message_id,
        message_id_header as message_id_header,
        in_reply_to,
        sent_at,
        _ingested_at,
        raw_subject,
        subject,
        raw_record,
        _connection_id,
        _stream_id,
        _sync_id,
        _account,
        _sync_metadata,
        source
    FROM cleaned_message
    -- Deduplication: keep latest message per message_id
    QUALIFY row_number() OVER (PARTITION BY message_id ORDER BY sent_at DESC) = 1
),

-- Build global thread_id by following in_reply_to chains to find root message
-- Use iterative self-joins instead of recursive CTE for BigQuery compatibility
-- Start with all messages pointing to themselves as potential roots
thread_roots_iter0 AS (
    SELECT 
        message_id,
        COALESCE(in_reply_to, message_id) as parent_id,
        message_id as root_message_id,
        0 as iteration
    FROM deduped_messages
),

-- Iteration 1: Follow one level up the chain
thread_roots_iter1 AS (
    SELECT 
        t0.message_id,
        COALESCE(t0_parent.in_reply_to, t0.parent_id) as parent_id,
        COALESCE(t0_parent.message_id, t0.root_message_id) as root_message_id,
        1 as iteration
    FROM thread_roots_iter0 t0
    LEFT JOIN deduped_messages t0_parent ON t0.parent_id = t0_parent.message_id
),

-- Iteration 2-5: Continue following the chain (most threads are < 5 levels)
thread_roots_iter2 AS (
    SELECT 
        t1.message_id,
        COALESCE(t1_parent.in_reply_to, t1.parent_id) as parent_id,
        COALESCE(t1_parent.message_id, t1.root_message_id) as root_message_id,
        2 as iteration
    FROM thread_roots_iter1 t1
    LEFT JOIN deduped_messages t1_parent ON t1.parent_id = t1_parent.message_id
),

thread_roots_iter3 AS (
    SELECT 
        t2.message_id,
        COALESCE(t2_parent.in_reply_to, t2.parent_id) as parent_id,
        COALESCE(t2_parent.message_id, t2.root_message_id) as root_message_id,
        3 as iteration
    FROM thread_roots_iter2 t2
    LEFT JOIN deduped_messages t2_parent ON t2.parent_id = t2_parent.message_id
),

thread_roots_iter4 AS (
    SELECT 
        t3.message_id,
        COALESCE(t3_parent.in_reply_to, t3.parent_id) as parent_id,
        COALESCE(t3_parent.message_id, t3.root_message_id) as root_message_id,
        4 as iteration
    FROM thread_roots_iter3 t3
    LEFT JOIN deduped_messages t3_parent ON t3.parent_id = t3_parent.message_id
),

thread_roots_iter5 AS (
    SELECT 
        t4.message_id,
        COALESCE(t4_parent.in_reply_to, t4.parent_id) as parent_id,
        COALESCE(t4_parent.message_id, t4.root_message_id) as root_message_id,
        5 as iteration
    FROM thread_roots_iter4 t4
    LEFT JOIN deduped_messages t4_parent ON t4.parent_id = t4_parent.message_id
),

-- Combine all iterations and pick the final root (from highest iteration)
thread_roots_combined AS (
    SELECT * FROM thread_roots_iter0
    UNION ALL SELECT * FROM thread_roots_iter1
    UNION ALL SELECT * FROM thread_roots_iter2
    UNION ALL SELECT * FROM thread_roots_iter3
    UNION ALL SELECT * FROM thread_roots_iter4
    UNION ALL SELECT * FROM thread_roots_iter5
),

-- Get the final root for each message (from the highest iteration)
thread_roots_deduped AS (
    SELECT 
        message_id,
        root_message_id
    FROM thread_roots_combined
    QUALIFY ROW_NUMBER() OVER (PARTITION BY message_id ORDER BY iteration DESC) = 1
),

-- For messages that couldn't be linked via in_reply_to (orphaned or missing parent),
-- use subject matching as fallback for grouping
subject_based_threads AS (
    SELECT 
        m.message_id,
        -- Use the earliest message_id with the same cleaned subject as thread root
        FIRST_VALUE(m.message_id) OVER (
            PARTITION BY m.subject 
            ORDER BY m.sent_at ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) as subject_thread_root
    FROM deduped_messages m
    LEFT JOIN thread_roots_deduped tr ON m.message_id = tr.message_id
    WHERE m.subject IS NOT NULL 
      AND m.subject != ''
      AND tr.message_id IS NULL  -- Only for messages not already in thread_roots
),

-- Combine thread roots: prefer in_reply_to chains, fall back to subject matching
-- If neither works, message is its own thread
thread_assignment AS (
    SELECT 
        m.*,
        COALESCE(
            tr.root_message_id,
            sbt.subject_thread_root,
            m.message_id  -- If no match, message is its own thread
        ) as thread_id
    FROM deduped_messages m
    LEFT JOIN thread_roots_deduped tr ON m.message_id = tr.message_id
    LEFT JOIN subject_based_threads sbt ON m.message_id = sbt.message_id
),

final as (  
SELECT 
    message_id,
    thread_id,
    gmail_thread_id,
    gmail_history_id,
    gmail_message_id,
    message_id_header,
    in_reply_to,
    sent_at,
    _ingested_at,
    raw_subject,
    subject,
    raw_record,
    _connection_id,
    _stream_id,
    _sync_id,
    _account,
    _sync_metadata,
    source
FROM thread_assignment
)

SELECT * FROM final
ORDER BY sent_at asc
