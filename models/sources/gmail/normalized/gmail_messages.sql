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
        _sync_timestamp,
        _sync_token,
        _raw_record
    FROM {{ ref('gmail_messages_base') }}
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
         LIMIT 1) as subject_header
    FROM source_data
),

-- Final cleaned message with subject, threads, body, etc.
cleaned_message AS (
    SELECT
        -- Message identifiers
        message_id,
        JSON_EXTRACT_SCALAR(_raw_record, '$.threadId') as thread_id,
        message_id_header,
        
        -- Timestamps
        TIMESTAMP_MILLIS(CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.internalDate') AS INT64)) as sent_at,
        
        
        -- Subject
        subject_header as subject,
        
        -- Body and attachments
        JSON_EXTRACT_SCALAR(_raw_record, '$.body_text') as body,
        JSON_EXTRACT_ARRAY(_raw_record, '$.attachments') as attachments_array,
        
        -- Sync metadata
        _ingested_at,
        _raw_record as raw_record,
        _connection_id,
        _stream_id,
        _sync_timestamp,
        _sync_token,
        'gmail' as source
    FROM headers_extracted
    WHERE message_id IS NOT NULL
)

SELECT 
    message_id_header as message_id,
    thread_id,
    message_id as gmail_message_id,
    message_id_header as message_id_header,
    sent_at,
    _ingested_at,
    subject,
    body,
    attachments_array,
    raw_record,
    _connection_id,
    _stream_id,
    _sync_timestamp,
    _sync_token,
    source
FROM cleaned_message
-- Deduplication: keep latest message per message_id
QUALIFY row_number() OVER (PARTITION BY message_id ORDER BY sent_at DESC) = 1
ORDER BY sent_at DESC
