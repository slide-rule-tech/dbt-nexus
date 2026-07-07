{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['event_id']),
    unique_key='event_id',
    on_schema_change='append_new_columns',
    tags=['gmail', 'intermediate', 'events']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'event_id']) }}

{% set bodies_enabled = var('nexus', {}).get('sources', {}).get('gmail', {}).get('bodies', false) %}
{% if bodies_enabled and nexus.nexus_incremental_enabled() %}
{# A body fetched AFTER its message was absorbed never re-offers the row
   (bodies ride fetched_at, not _ingested_at), so the joined body columns
   would freeze as NULL forever. No client runs this combination; make it
   impossible to hit silently. #}
{{ exceptions.raise_compiler_error("gmail bodies + nexus.incremental.enabled is not supported yet: late-fetched bodies never re-offer their message row. Disable one of the two.") }}
{% endif %}

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
{% if is_incremental() %}
WHERE m._ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
{% endif %}

