{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized', 'by_account']
) }}

-- Per-account normalization: Clean messages using gmail_message_id (not cross-account)
-- Extracts data from new STANDARD_TABLE_SCHEMA with _raw_record and headers array
WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') as gmail_message_id,
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

-- Final cleaned message with subject, etc. (per-account only)
cleaned_message AS (
    SELECT
        -- Message identifiers (per-account)
        gmail_message_id,
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

        -- Labels
        ARRAY(SELECT JSON_EXTRACT_SCALAR(label, '$') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.labelIds')) as label) as label_ids,

        -- Message content
        {{ nexus.html_decode("JSON_EXTRACT_SCALAR(_raw_record, '$.snippet')") }} as snippet,
        CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.sizeEstimate') AS INT64) as size_estimate,

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
    WHERE gmail_message_id IS NOT NULL
)


SELECT * FROM cleaned_message
ORDER BY sent_at ASC

