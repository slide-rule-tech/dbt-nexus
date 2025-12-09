{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized']
) }}

-- Normalized threads: Aggregate messages by global thread_id
-- Groups messages across streams using in_reply_to chains and subject matching
WITH messages AS (
    SELECT * FROM {{ ref('gmail_messages') }}
),

-- Build stream to gmail_thread_id mapping for each thread
stream_thread_counts AS (
    SELECT
        thread_id,
        _stream_id,
        gmail_thread_id,
        COUNT(*) as thread_id_count,
        MIN(sent_at) as first_sent_at
    FROM messages
    WHERE thread_id IS NOT NULL 
      AND gmail_thread_id IS NOT NULL
      AND _stream_id IS NOT NULL
    GROUP BY thread_id, _stream_id, gmail_thread_id
),

stream_thread_mapping AS (
    SELECT
        thread_id,
        _stream_id,
        -- For each stream, get the most common gmail_thread_id (or first if tie)
        ARRAY_AGG(gmail_thread_id ORDER BY thread_id_count DESC, first_sent_at ASC LIMIT 1)[OFFSET(0)] as gmail_thread_id
    FROM stream_thread_counts
    GROUP BY thread_id, _stream_id
),

thread_summary AS (
    SELECT
        thread_id,
        
        -- Thread metadata
        COUNT(*) as message_count,
        COUNT(DISTINCT _stream_id) as stream_count,
        COUNT(DISTINCT gmail_thread_id) as gmail_thread_count,
        
        -- Subject (use the root message's subject, or most common if no clear root)
        ARRAY_AGG(subject ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as subject,
        ARRAY_AGG(raw_subject ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as raw_subject,
        
        -- Timestamps
        MIN(sent_at) as thread_started_at,
        MAX(sent_at) as thread_last_message_at,
        MIN(_ingested_at) as first_ingested_at,
        MAX(_ingested_at) as last_ingested_at,
        
        -- Root message info
        ARRAY_AGG(message_id ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)] as root_message_id,
        
        -- Streams involved
        ARRAY_AGG(DISTINCT _stream_id) as streams,
        
        -- Gmail thread IDs (account-specific)
        ARRAY_AGG(DISTINCT gmail_thread_id IGNORE NULLS) as gmail_thread_ids
    FROM messages
    WHERE thread_id IS NOT NULL
    GROUP BY thread_id
),

-- Build JSON string for stream to gmail_thread_id mapping
threads_with_mapping AS (
    SELECT 
        ts.*,
        -- Create JSON object mapping email (stream_id) to gmail_thread_id
        -- Format: {"email1": "thread_id1", "email2": "thread_id2"}
        CONCAT(
            '{',
            STRING_AGG(
                CONCAT('"', stm._stream_id, '": "', stm.gmail_thread_id, '"'),
                ', '
                ORDER BY stm._stream_id
            ),
            '}'
        ) as stream_gmail_thread_ids
    FROM thread_summary ts
    LEFT JOIN stream_thread_mapping stm ON ts.thread_id = stm.thread_id
    GROUP BY 
        ts.thread_id,
        ts.message_count,
        ts.stream_count,
        ts.gmail_thread_count,
        ts.subject,
        ts.raw_subject,
        ts.thread_started_at,
        ts.thread_last_message_at,
        ts.first_ingested_at,
        ts.last_ingested_at,
        ts.root_message_id,
        ts.streams,
        ts.gmail_thread_ids
),

final as (

SELECT 
    thread_id,
    message_count,
    stream_count,
    gmail_thread_count,
    subject,
    raw_subject,
    thread_started_at,
    thread_last_message_at,
    first_ingested_at,
    last_ingested_at,
    root_message_id,
    streams,
    gmail_thread_ids,
    COALESCE(stream_gmail_thread_ids, '{}') as stream_gmail_thread_ids
FROM threads_with_mapping
ORDER BY thread_last_message_at DESC

)

select * from final