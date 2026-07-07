{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['gmail_message_id']),
    unique_key=['gmail_message_id', '_account'],
    on_schema_change='append_new_columns',
    tags=['gmail', 'normalized', 'by_account']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'gmail_message_id']) }}

{% set internal_domains = var('internal_domains', []) %}
{% set filter_internal_only_messages = var('nexus', {}).get('sources', {}).get('gmail', {}).get('filter_internal_only_messages', false) %}
{% set should_filter_internal_only_messages = filter_internal_only_messages and (internal_domains | length > 0) %}
{% if is_incremental() %}
{# ONE literal shared by both batch filters below: source_data and
   participant_domain_summary propagate the same base row's _ingested_at,
   so a single watermark guarantees the domain summary covers exactly the
   batch's messages. #}
{% set wm = nexus.nexus_incremental_watermark_literal('_ingested_at') %}
{% endif %}

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
    {% if is_incremental() %}
    WHERE _ingested_at > {{ wm }}
    {% endif %}
),

-- Extract headers for message-level data only
headers_extracted AS (
    SELECT
        *,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as {% if target.type == 'duckdb' %}t(header){% else %}header{% endif %}
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'message-id'
         LIMIT 1) as message_id_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as {% if target.type == 'duckdb' %}t(header){% else %}header{% endif %}
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'subject'
         LIMIT 1) as subject_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as {% if target.type == 'duckdb' %}t(header){% else %}header{% endif %}
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'in-reply-to'
         LIMIT 1) as in_reply_to_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as {% if target.type == 'duckdb' %}t(header){% else %}header{% endif %}
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'auto-submitted'
         LIMIT 1) as auto_submitted_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as {% if target.type == 'duckdb' %}t(header){% else %}header{% endif %}
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'precedence'
         LIMIT 1) as precedence_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as {% if target.type == 'duckdb' %}t(header){% else %}header{% endif %}
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'list-id'
         LIMIT 1) as list_id_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as {% if target.type == 'duckdb' %}t(header){% else %}header{% endif %}
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'list-unsubscribe'
         LIMIT 1) as list_unsubscribe_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as {% if target.type == 'duckdb' %}t(header){% else %}header{% endif %}
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'x-auto-response-suppress'
         LIMIT 1) as x_auto_response_suppress_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as {% if target.type == 'duckdb' %}t(header){% else %}header{% endif %}
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'x-autoreply'
         LIMIT 1) as x_autoreply_header,
        (SELECT JSON_EXTRACT_SCALAR(header, '$.value') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as {% if target.type == 'duckdb' %}t(header){% else %}header{% endif %}
         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'x-autorespond'
         LIMIT 1) as x_autorespond_header
    FROM source_data
),

participant_domain_summary AS (
    SELECT
        gmail_message_id,
        _account,
        COUNT(*) as participant_count,
        {% if target.type == 'bigquery' -%}
        ARRAY_AGG(DISTINCT LOWER(domain) IGNORE NULLS ORDER BY LOWER(domain)) as participant_domains,
        {%- else -%}
        ARRAY_AGG(DISTINCT LOWER(domain) ORDER BY LOWER(domain)) FILTER (WHERE domain IS NOT NULL) as participant_domains,
        {%- endif %}
        {% if internal_domains | length > 0 %}
        COUNTIF(
            domain IN (
                {%- for domain in internal_domains -%}
                '{{ domain | lower }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            )
        ) as internal_participant_count,
        COUNTIF(
            domain NOT IN (
                {%- for domain in internal_domains -%}
                '{{ domain | lower }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            )
        ) as external_participant_count
        {% else %}
        0 as internal_participant_count,
        COUNT(*) as external_participant_count
        {% endif %}
    FROM {{ ref('gmail_message_participants_by_account') }}
    {% if is_incremental() %}
    WHERE _ingested_at > {{ wm }}
    {% endif %}
    GROUP BY gmail_message_id, _account
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
        auto_submitted_header,
        precedence_header,
        list_id_header,
        list_unsubscribe_header,
        x_auto_response_suppress_header,
        x_autoreply_header,
        x_autorespond_header,
        
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
                            {% if target.type == 'bigquery' %}r'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*'{% else %}'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*'{% endif %},
                            ''
                        ),
                        {% if target.type == 'bigquery' %}r'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*'{% else %}'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*'{% endif %},
                        ''
                    ),
                    {% if target.type == 'bigquery' %}r'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*'{% else %}'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*'{% endif %},
                    ''
                ),
                {% if target.type == 'bigquery' %}r'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*'{% else %}'^([Rr][Ee]|[Ff][Ww][Dd]?):\s*'{% endif %},
                ''
            )
        ) as subject,

        -- Labels
        ARRAY(SELECT JSON_EXTRACT_SCALAR(label, '$') FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.labelIds')) as {% if target.type == 'duckdb' %}t(label){% else %}label{% endif %}) as label_ids,

        -- Message content
        {{ nexus.html_decode("JSON_EXTRACT_SCALAR(_raw_record, '$.snippet')") }} as snippet,
        CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.sizeEstimate') AS INT64) as size_estimate,
        (
            REGEXP_CONTAINS(LOWER(COALESCE(auto_submitted_header, '')), {% if target.type == 'bigquery' %}r'^auto-'{% else %}'^auto-'{% endif %})
            OR LOWER(COALESCE(precedence_header, '')) IN ('bulk', 'list', 'junk')
            OR COALESCE(NULLIF(TRIM(list_id_header), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(list_unsubscribe_header), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(x_auto_response_suppress_header), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(x_autoreply_header), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(x_autorespond_header), ''), NULL) IS NOT NULL
        ) as is_automated_or_bulk_message,

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
),

filtered_message AS (
    SELECT
        cm.*,
        COALESCE(pds.participant_domains, {% if target.type == 'bigquery' %}CAST([] AS ARRAY<STRING>){% else %}CAST([] AS VARCHAR[]){% endif %}) as participant_domains,
        (
            COALESCE(pds.participant_count, 0) > 0
            AND COALESCE(pds.external_participant_count, 0) = 0
        ) as is_internal_only_message,
        {% if target.type == 'bigquery' -%}
        TO_JSON_STRING(STRUCT(
            COALESCE(pds.participant_count, 0) as participant_count,
            COALESCE(pds.internal_participant_count, 0) as internal_participant_count,
            COALESCE(pds.external_participant_count, 0) as external_participant_count,
            COALESCE(pds.participant_domains, CAST([] AS ARRAY<STRING>)) as domains
        )) as participant_domain_summary
        {%- else -%}
        cast(to_json({
            'participant_count': COALESCE(pds.participant_count, 0),
            'internal_participant_count': COALESCE(pds.internal_participant_count, 0),
            'external_participant_count': COALESCE(pds.external_participant_count, 0),
            'domains': COALESCE(pds.participant_domains, CAST([] AS VARCHAR[]))
        }) AS varchar) as participant_domain_summary
        {%- endif %}
    FROM cleaned_message cm
    LEFT JOIN participant_domain_summary pds
        ON cm.gmail_message_id = pds.gmail_message_id
        AND cm._account = pds._account
    {% if should_filter_internal_only_messages %}
    WHERE (
        -- Keep messages when we cannot parse participants.
        COALESCE(pds.participant_count, 0) = 0
        -- Keep messages with at least one external participant.
        OR COALESCE(pds.external_participant_count, 0) > 0
    )
    {% endif %}
)


SELECT * FROM filtered_message

