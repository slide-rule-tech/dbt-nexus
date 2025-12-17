{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized']
) }}

-- Cross-account normalized messages: Group per-account messages by message_id_header
-- Join with per-account threads to get thread_id from first_message_id_header
WITH per_account_messages AS (
    SELECT * FROM {{ ref('gmail_messages_by_account') }}
),

per_account_threads AS (
    SELECT * FROM {{ ref('gmail_threads_by_account') }}
),

-- Cross-account deduplication: group by message_id_header, keep latest
grouped_messages AS (
    SELECT 
        message_id_header as message_id,
        message_id_header,
        ARRAY_AGG(in_reply_to ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)] as in_reply_to,
        MAX(sent_at) as sent_at,
        ARRAY_AGG(raw_subject ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)] as raw_subject,
        ARRAY_AGG(subject ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)] as subject,
        ARRAY_AGG(raw_record ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)] as raw_record,
        ARRAY_AGG(snippet ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)] as snippet,
        ARRAY_AGG(size_estimate ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)] as size_estimate,
        'gmail' as source,
        MAX(_ingested_at) as _ingested_at,
        -- Get the latest gmail_thread_id and _account for joining with threads
        ARRAY_AGG(gmail_thread_id ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)] as last_gmail_thread_id,
        ARRAY_AGG(_account ORDER BY sent_at DESC LIMIT 1)[OFFSET(0)] as _account,
        -- Create JSON object mapping email (stream_id) to gmail_message_id
        -- Format: {"email1": "message_id1", "email2": "message_id2"}
        CONCAT(
            '{',
            STRING_AGG(
                CONCAT('"', _stream_id, '": "', gmail_message_id, '"'),
                ', '
                ORDER BY _stream_id
            ),
            '}'
        ) as gmail_message_ids,
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
        ) as label_ids
    FROM per_account_messages
    WHERE message_id_header IS NOT NULL
    GROUP BY message_id_header
),

-- Get all unique label IDs across all streams for each message
all_labels AS (
    SELECT 
        message_id_header,
        ARRAY(
            SELECT DISTINCT label_id
            FROM UNNEST(label_ids) as label_id
            ORDER BY label_id
        ) as all_label_ids
    FROM (
        SELECT 
            message_id_header,
            ARRAY_CONCAT_AGG(label_ids) as label_ids
        FROM per_account_messages
        WHERE message_id_header IS NOT NULL
        GROUP BY message_id_header
    )
),

joined as (
    SELECT 
        gm.message_id,
        gm.sent_at,
        pat.first_message_id_header as thread_id,
        gm.subject,
        gm.in_reply_to,
        gm.raw_subject,
        gm.raw_record,
        gm.snippet,
        gm.size_estimate,
        gm.source,
        gm._ingested_at,
        gm.gmail_message_ids,
        gm.label_ids,
        al.all_label_ids
    FROM grouped_messages gm
    LEFT JOIN per_account_threads pat 
        ON gm.last_gmail_thread_id = pat.gmail_thread_id
        AND gm._account = pat._account
    LEFT JOIN all_labels al
        ON gm.message_id_header = al.message_id_header
)

select * from joined
ORDER BY sent_at desc
