{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'events']
) }}

{% set bodies_enabled = var('nexus', {}).get('sources', {}).get('gmail', {}).get('bodies', false) %}

-- Extract message events from normalized gmail messages
SELECT
    {{ nexus.create_nexus_id('event', ['m.message_id']) }} as event_id,
    m.sent_at as occurred_at,
    'message sent' as event_name,
    'email' as event_type,
    m.subject as event_description,
    CASE
        WHEN COALESCE(m.is_automated_or_bulk_message, FALSE) THEN -10
        ELSE 10
    END as significance,
    'gmail' as source,
    'gmail_message_events' as source_table,
    m._ingested_at,

    -- Additional fields
    m.message_id,
    m.thread_id,
    m.gmail_message_ids,
    m.gmail_thread_ids,
    m.sent_at,
    m.subject,
    m.in_reply_to,
    m.auto_submitted_header,
    m.precedence_header,
    m.list_id_header,
    m.list_unsubscribe_header,
    m.x_auto_response_suppress_header,
    m.x_autoreply_header,
    m.x_autorespond_header,
    m.is_automated_or_bulk_message,
    m.raw_subject,
    m.snippet,
    m.size_estimate,
    m.label_ids,
    m.all_label_ids,

    -- Email body (pulled on demand by the gmail_message_body enricher). NULL /
    -- FALSE when bodies aren't enabled or haven't been fetched for this message.
    {% if bodies_enabled %}
    b.body_text,
    b.body_truncated,
    (b.message_id_header IS NOT NULL) AS has_body
    {% else %}
    CAST(NULL AS {{ dbt.type_string() }}) as body_text,
    CAST(NULL AS {{ dbt.type_boolean() }}) as body_truncated,
    FALSE as has_body
    {% endif %}

FROM {{ ref('gmail_messages') }} m
{% if bodies_enabled %}
LEFT JOIN {{ ref('gmail_message_bodies') }} b
    ON m.message_id = b.message_id_header
{% endif %}

