{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'normalized', 'by_account']
) }}

-- Per-account normalized participants: Extract, parse, and normalize all participants (senders and recipients) from Gmail messages
-- Creates one row per participant per message, with role indicating "sender", "recipient", "cced", or "bcced"
-- Uses gmail_message_id (per-account) instead of message_id_header (cross-account)
WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') as gmail_message_id,
        TIMESTAMP_MILLIS(CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.internalDate') AS INT64)) as sent_at,
        _ingested_at,
        _account,
        _raw_record
    FROM {{ ref('gmail_messages_base_dedupped') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
),

-- Extract headers (message-id, from, to, cc, bcc)
headers_extracted AS (
    SELECT
        gmail_message_id,
        sent_at,
        _ingested_at,
        _account,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'message-id'
         LIMIT 1) as message_id_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'from'
         LIMIT 1) as from_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'to'
         LIMIT 1) as to_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'cc'
         LIMIT 1) as cc_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'bcc'
         LIMIT 1) as bcc_header
    FROM source_data
),

-- Extract and normalize senders (from "from" header)
senders_raw AS (
    SELECT
        gmail_message_id,
        sent_at,
        _ingested_at,
        _account,
        from_header as participant_raw,
        {{ nexus.parse_gmail_email('from_header') }} as parsed_email,
        {{ nexus.extract_gmail_name('from_header') }} as participant_name
    FROM headers_extracted
    WHERE from_header IS NOT NULL
),

senders_normalized AS (
    SELECT
        gmail_message_id,
        sent_at,
        _ingested_at,
        _account,
        participant_raw,
        participant_name,
        parsed_email,
        {{ nexus.validate_and_normalize_email('parsed_email') }} as normalized_email,
        'sender' as role
    FROM senders_raw
    WHERE {{ nexus.validate_and_normalize_email('parsed_email') }} IS NOT NULL
),

-- Extract and normalize "to" recipients
to_recipients_parsed AS (
    SELECT
        h.gmail_message_id,
        h.sent_at,
        h._ingested_at,
        h._account,
        TRIM(recipient) as participant_raw,
        {{ nexus.parse_gmail_email('TRIM(recipient)') }} as parsed_email,
        {{ nexus.extract_gmail_name('TRIM(recipient)') }} as participant_name
    FROM headers_extracted h,
    UNNEST(SPLIT(COALESCE(h.to_header, ''), ',')) as recipient
    WHERE h.to_header IS NOT NULL
    AND TRIM(recipient) != ''
),

to_recipients_normalized AS (
    SELECT
        gmail_message_id,
        sent_at,
        _ingested_at,
        _account,
        participant_raw,
        participant_name,
        parsed_email,
        {{ nexus.validate_and_normalize_email('parsed_email') }} as normalized_email,
        'recipient' as role
    FROM to_recipients_parsed
    WHERE {{ nexus.validate_and_normalize_email('parsed_email') }} IS NOT NULL
),

-- Extract and normalize "cc" recipients
cc_recipients_parsed AS (
    SELECT
        h.gmail_message_id,
        h.sent_at,
        h._ingested_at,
        h._account,
        TRIM(recipient) as participant_raw,
        {{ nexus.parse_gmail_email('TRIM(recipient)') }} as parsed_email,
        {{ nexus.extract_gmail_name('TRIM(recipient)') }} as participant_name
    FROM headers_extracted h,
    UNNEST(SPLIT(COALESCE(h.cc_header, ''), ',')) as recipient
    WHERE h.cc_header IS NOT NULL
    AND TRIM(recipient) != ''
),

cc_recipients_normalized AS (
    SELECT
        gmail_message_id,
        sent_at,
        _ingested_at,
        _account,
        participant_raw,
        participant_name,
        parsed_email,
        {{ nexus.validate_and_normalize_email('parsed_email') }} as normalized_email,
        'cced' as role
    FROM cc_recipients_parsed
    WHERE {{ nexus.validate_and_normalize_email('parsed_email') }} IS NOT NULL
),

-- Extract and normalize "bcc" recipients
bcc_recipients_parsed AS (
    SELECT
        h.gmail_message_id,
        h.sent_at,
        h._ingested_at,
        h._account,
        TRIM(recipient) as participant_raw,
        {{ nexus.parse_gmail_email('TRIM(recipient)') }} as parsed_email,
        {{ nexus.extract_gmail_name('TRIM(recipient)') }} as participant_name
    FROM headers_extracted h,
    UNNEST(SPLIT(COALESCE(h.bcc_header, ''), ',')) as recipient
    WHERE h.bcc_header IS NOT NULL
    AND TRIM(recipient) != ''
),

bcc_recipients_normalized AS (
    SELECT
        gmail_message_id,
        sent_at,
        _ingested_at,
        _account,
        participant_raw,
        participant_name,
        parsed_email,
        {{ nexus.validate_and_normalize_email('parsed_email') }} as normalized_email,
        'bcced' as role
    FROM bcc_recipients_parsed
    WHERE {{ nexus.validate_and_normalize_email('parsed_email') }} IS NOT NULL
),

-- Union all participants (senders and recipients)
participants_combined AS (
    SELECT
        gmail_message_id,
        sent_at,
        _ingested_at,
        _account,
        participant_raw,
        participant_name,
        parsed_email,
        normalized_email,
        role
    FROM senders_normalized
    
    UNION ALL
    
    SELECT
        gmail_message_id,
        sent_at,
        _ingested_at,
        _account,
        participant_raw,
        participant_name,
        parsed_email,
        normalized_email,
        role
    FROM to_recipients_normalized
    
    UNION ALL
    
    SELECT
        gmail_message_id,
        sent_at,
        _ingested_at,
        _account,
        participant_raw,
        participant_name,
        parsed_email,
        normalized_email,
        role
    FROM cc_recipients_normalized
    
    UNION ALL
    
    SELECT
        gmail_message_id,
        sent_at,
        _ingested_at,
        _account,
        participant_raw,
        participant_name,
        parsed_email,
        normalized_email,
        role
    FROM bcc_recipients_normalized
),

-- Per-account deduplication: same gmail_message_id, email, and role can appear multiple times
-- due to multiple ingestions. Keep the most recent ingestion.
SELECT 
    gmail_message_id,
    participant_raw,
    TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(participant_name, r'^[\'"]+', ''),
            r'[\'"]+$', 
            ''
        )
    ) as name,
    normalized_email as email,
    SPLIT(normalized_email, '@')[SAFE_OFFSET(1)] as domain,
    role,
    sent_at,
    _ingested_at,
    _account
FROM participants_combined
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY gmail_message_id, _account, normalized_email, role 
    ORDER BY _ingested_at DESC, sent_at DESC
) = 1
ORDER BY gmail_message_id, 
    CASE role 
        WHEN 'sender' THEN 1
        WHEN 'recipient' THEN 2
        WHEN 'cced' THEN 3
        WHEN 'bcced' THEN 4
    END,
    email

