{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized', 'by_account']
) }}

-- Per-account normalized threads: Aggregate messages by gmail_thread_id (per account)
-- Uses Gmail's native thread_id for per-account threading
WITH messages AS (
    SELECT * FROM {{ ref('gmail_messages_by_account') }}
),

thread_summary AS (
    SELECT
        gmail_thread_id,
        _account,
        _stream_id,
        
        -- Thread metadata
        COUNT(*) as message_count,
        COUNT(DISTINCT gmail_message_id) as gmail_message_count,
        
        -- Subject (use the earliest message's subject)
        ARRAY_AGG(subject ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as subject,
        ARRAY_AGG(raw_subject ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as raw_subject,
        
        -- Timestamps
        MIN(sent_at) as first_message_sent_at,
        MAX(sent_at) as last_message_sent_at,
        MIN(_ingested_at) as first_ingested_at,
        MAX(_ingested_at) as last_ingested_at,
        
        -- Root message info (earliest gmail_message_id)
        ARRAY_AGG(gmail_message_id ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as root_gmail_message_id,
        
        -- First message_id_header (earliest message's message_id_header for cross-account linking)
        ARRAY_AGG(message_id_header ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as first_message_id_header,
        
        -- Gmail message IDs in thread
        ARRAY_AGG(DISTINCT gmail_message_id) as gmail_message_ids
    FROM messages
    WHERE gmail_thread_id IS NOT NULL
      AND _account IS NOT NULL
    GROUP BY gmail_thread_id, _account, _stream_id
),

-- Get all unique label IDs from all messages in each thread
thread_labels AS (
    SELECT 
        gmail_thread_id,
        _account,
        _stream_id,
        ARRAY(
            SELECT DISTINCT label_id
            FROM UNNEST(label_ids) as label_id
            ORDER BY label_id
        ) as label_ids
    FROM (
        SELECT 
            gmail_thread_id,
            _account,
            _stream_id,
            ARRAY_CONCAT_AGG(label_ids) as label_ids
        FROM messages
        WHERE gmail_thread_id IS NOT NULL
          AND _account IS NOT NULL
        GROUP BY gmail_thread_id, _account, _stream_id
    )
)

SELECT 
    ts.gmail_thread_id,
    ts.message_count,
    ts.gmail_message_count,
    ts.subject,
    ts.raw_subject,
    ts.first_message_sent_at,
    ts.last_message_sent_at,
    ts.root_gmail_message_id,
    ts.first_message_id_header,
    ts.first_ingested_at as _ingested_at,
    ts._account,
    ts._stream_id,
    tl.label_ids
FROM thread_summary ts
LEFT JOIN thread_labels tl
    ON ts.gmail_thread_id = tl.gmail_thread_id
    AND ts._account = tl._account
    AND ts._stream_id = tl._stream_id
ORDER BY ts.last_message_sent_at DESC

