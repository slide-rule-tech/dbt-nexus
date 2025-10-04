{{ config(
    enabled=var('nexus', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(record, '$.id') as message_id,
        *
    FROM {{ nexus_source('gmail', 'messages') }}
),


extracted AS (
    SELECT
        {{ create_nexus_id('event', ['message_id']) }} as event_id,
        'message_sent' as event_name,
        CAST(PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', JSON_EXTRACT_SCALAR(record, '$.date')) AS TIMESTAMP) as occurred_at,
        
        -- Message details
        message_id,
        JSON_EXTRACT_SCALAR(record, '$.threadId') as thread_id,
        JSON_EXTRACT_SCALAR(record, '$.sender') as sender_raw,
        JSON_EXTRACT_SCALAR(record, '$.recipients') as recipients_raw,
        JSON_EXTRACT_SCALAR(record, '$.subject') as subject,
        JSON_EXTRACT_SCALAR(record, '$.body') as body,
        
        -- Parsed sender
        STRUCT(
            {{ parse_gmail_email('JSON_EXTRACT_SCALAR(record, "$.sender")') }} as email,
            {{ extract_gmail_name('JSON_EXTRACT_SCALAR(record, "$.sender")') }} as name,
            REGEXP_EXTRACT({{ parse_gmail_email('JSON_EXTRACT_SCALAR(record, "$.sender")') }}, r'@(.+)') as domain,
            REGEXP_EXTRACT({{ parse_gmail_email('JSON_EXTRACT_SCALAR(record, "$.sender")') }}, r'@(.+)') IN (
                'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 
                'aol.com', 'icloud.com', 'me.com', 'live.com', 'msn.com',
                'googlemail.com', 'ymail.com', 'rocketmail.com', 'protonmail.com',
                'mail.com', 'zoho.com'
            ) as generic_domain,
            REGEXP_EXTRACT({{ parse_gmail_email('JSON_EXTRACT_SCALAR(record, "$.sender")') }}, r'@(.+)') IN (
                {%- for domain in var('internal_domains') -%}
                '{{ domain }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            ) as internal,
            {{ parse_gmail_email('JSON_EXTRACT_SCALAR(record, "$.sender")') }} IN (
                {%- for email in var('test_emails') -%}
                '{{ email }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            ) as test
        ) as sender,
        
        -- Parsed recipients array
        ARRAY(
            SELECT AS STRUCT
                {{ parse_gmail_email('TRIM(recipient)') }} as email,
                {{ extract_gmail_name('TRIM(recipient)') }} as name,
                REGEXP_EXTRACT({{ parse_gmail_email('TRIM(recipient)') }}, r'@(.+)') as domain,
                REGEXP_EXTRACT({{ parse_gmail_email('TRIM(recipient)') }}, r'@(.+)') IN (
                    'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 
                    'aol.com', 'icloud.com', 'me.com', 'live.com', 'msn.com',
                    'googlemail.com', 'ymail.com', 'rocketmail.com', 'protonmail.com',
                    'mail.com', 'zoho.com'
                ) as generic_domain,
                REGEXP_EXTRACT({{ parse_gmail_email('TRIM(recipient)') }}, r'@(.+)') IN (
                    {%- for domain in var('internal_domains') -%}
                    '{{ domain }}'
                    {%- if not loop.last -%},{%- endif -%}
                    {%- endfor -%}
                ) as internal,
                {{ parse_gmail_email('TRIM(recipient)') }} IN (
                    {%- for email in var('test_emails') -%}
                    '{{ email }}'
                    {%- if not loop.last -%},{%- endif -%}
                    {%- endfor -%}
                ) as test
            FROM UNNEST(SPLIT(JSON_EXTRACT_SCALAR(record, '$.recipients'), ',')) as recipient
            WHERE TRIM(recipient) IS NOT NULL 
            AND TRIM(recipient) != ''
            AND {{ parse_gmail_email('TRIM(recipient)') }} IS NOT NULL
            AND {{ parse_gmail_email('TRIM(recipient)') }} != ''
        ) as recipients,
        
        -- Keep the original record for reference
        record as raw_record,
        synced_at
    FROM source_data
),

with_latest_events AS (
    {{ get_first_or_last_row(
        source='extracted',
        partition_by='message_id',
        order_by='occurred_at',
        column_label='is_latest',
        get='last'
    ) }}
),

deduped_events AS (
    SELECT *
    FROM with_latest_events
    WHERE is_latest
),

final AS (
    SELECT 
        *,
        'gmail' as source,
        subject as event_description
    FROM deduped_events
)

SELECT * FROM final
ORDER BY occurred_at DESC
