{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized']
) }}

-- Cross-account normalized threads: Group per-account threads by first_message_id_header
WITH per_account_threads AS (
    SELECT * FROM {{ ref('gmail_threads_by_account') }}
),

grouped as (
    SELECT 
        first_message_id_header as thread_id,
        ARRAY_AGG(subject ORDER BY first_message_sent_at ASC LIMIT 1)[OFFSET(0)] as subject,
        ARRAY_AGG(raw_subject ORDER BY first_message_sent_at ASC LIMIT 1)[OFFSET(0)] as raw_subject,
        MIN(first_message_sent_at) as first_message_sent_at,
        MAX(last_message_sent_at) as last_message_sent_at,
        
        -- Create JSON object mapping email (stream_id) to gmail_thread_id
        -- Format: {"email1": "thread_id1", "email2": "thread_id2"}
        CONCAT(
            '{',
            STRING_AGG(
                CONCAT('"', _stream_id, '": "', gmail_thread_id, '"'),
                ', '
                ORDER BY _stream_id
            ),
            '}'
        ) as gmail_thread_ids,
        -- Create JSON object mapping email (stream_id) to label_ids array
        -- Format: {"email1": ["label1", "label2"], "email2": ["label3"]}
        CONCAT(
            '{',
            STRING_AGG(
                CONCAT(
                    '"', _stream_id, '": ',
                    TO_JSON_STRING(label_ids)
                ),
                ', '
                ORDER BY _stream_id
            ),
            '}'
        ) as label_ids,
        MIN(_ingested_at) as _ingested_at,
    FROM per_account_threads
    WHERE first_message_id_header IS NOT NULL
    GROUP BY first_message_id_header
),

-- Get all unique label IDs across all streams for each thread
all_labels AS (
    SELECT 
        first_message_id_header,
        ARRAY(
            SELECT DISTINCT label_id
            FROM UNNEST(label_ids) as label_id
            ORDER BY label_id
        ) as all_label_ids
    FROM (
        SELECT 
            first_message_id_header,
            ARRAY_CONCAT_AGG(label_ids) as label_ids
        FROM per_account_threads
        WHERE first_message_id_header IS NOT NULL
        GROUP BY first_message_id_header
    )
)

SELECT 
    g.thread_id,
    g.subject,
    g.raw_subject,
    g.first_message_sent_at,
    g.last_message_sent_at,
    g.gmail_thread_ids,
    g.label_ids,
    al.all_label_ids,
    g._ingested_at
FROM grouped g
LEFT JOIN all_labels al
    ON g.thread_id = al.first_message_id_header
ORDER BY g.last_message_sent_at DESC