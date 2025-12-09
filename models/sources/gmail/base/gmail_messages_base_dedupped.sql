{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='view',
    tags=['gmail', 'base']
) }}

-- Deduplicated base layer: Deduplicates messages based on Gmail message ID
-- Keeps the most recent ingestion when the same message appears multiple times
WITH source_data AS (
    SELECT 
        *,
        JSON_EXTRACT_SCALAR(_raw_record, '$.id') as gmail_message_id
    FROM {{ ref('gmail_messages_base') }}
    WHERE JSON_EXTRACT_SCALAR(_raw_record, '$.id') IS NOT NULL
),

deduplicated AS (
    SELECT 
        * EXCEPT(gmail_message_id),
        ROW_NUMBER() OVER (
            PARTITION BY gmail_message_id 
            ORDER BY _ingested_at DESC
        ) as rn
    FROM source_data
)

SELECT 
    _ingested_at,
    _connection_id,
    _stream_id,
    _raw_record,
    _sync_id,
    _account,
    _sync_metadata
FROM deduplicated
WHERE rn = 1

