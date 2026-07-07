{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['message_id']),
    unique_key=['message_id', 'email', 'role'],
    on_schema_change='append_new_columns',
    tags=['gmail', 'normalized']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_watermark_ingested_at', 'message_id']) }}

{% if is_incremental() %}
{% set wm = nexus.nexus_incremental_watermark_literal('_watermark_ingested_at') %}
{% endif %}

-- Cross-account normalized participants: Group per-account participants by message_id_header
--
-- Touched-group rollup: touched headers = headers of batch participants
-- UNION headers of batch messages (a re-synced message can remap its
-- header), recomputed from full history and merged on the output grain.
WITH per_account_participants_all AS (
    SELECT
        p.participant_raw,
        p.name,
        p.email,
        p.domain,
        p.role,
        p.sent_at,
        p._ingested_at,
        m._ingested_at as _message_ingested_at,
        m.message_id_header as message_id
    FROM {{ ref('gmail_message_participants_by_account') }} p
    INNER JOIN {{ ref('gmail_messages_by_account') }} m 
        ON p.gmail_message_id = m.gmail_message_id 
        AND p._account = m._account
    WHERE m.message_id_header IS NOT NULL
),

{% if is_incremental() %}
touched_headers AS (
    SELECT DISTINCT message_id
    FROM per_account_participants_all
    WHERE _ingested_at > {{ wm }} OR _message_ingested_at > {{ wm }}
),
{% endif %}

per_account_participants AS (
    SELECT pa.* FROM per_account_participants_all pa
    {% if is_incremental() %}
    INNER JOIN touched_headers th ON pa.message_id = th.message_id
    {% endif %}
),

-- Cross-account deduplication: group by message_id_header, email, and role
-- Keep the most recent record for each participant
grouped_participants AS (
    SELECT 
        message_id,
        email,
        role,
        {% if target.type == 'bigquery' %}ARRAY_AGG(participant_raw ORDER BY sent_at DESC, _ingested_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(participant_raw ORDER BY sent_at DESC, _ingested_at DESC){% endif %} as participant_raw,
        {% if target.type == 'bigquery' %}ARRAY_AGG(name ORDER BY sent_at DESC, _ingested_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(name ORDER BY sent_at DESC, _ingested_at DESC){% endif %} as name,
        {% if target.type == 'bigquery' %}ARRAY_AGG(domain ORDER BY sent_at DESC, _ingested_at DESC LIMIT 1)[OFFSET(0)]{% else %}first(domain ORDER BY sent_at DESC, _ingested_at DESC){% endif %} as domain,
        MAX(sent_at) as sent_at,
        MAX(_ingested_at) as _ingested_at,
        GREATEST(MAX(_ingested_at), MAX(_message_ingested_at)) as _watermark_ingested_at
    FROM per_account_participants
    WHERE message_id IS NOT NULL
    GROUP BY message_id, email, role
),

final as (
SELECT 
    message_id,
    participant_raw,
    name,
    email,
    domain,
    role,
    sent_at,
    _ingested_at,
    _watermark_ingested_at
FROM grouped_participants
ORDER BY message_id, 
    CASE role 
        WHEN 'sender' THEN 1
        WHEN 'recipient' THEN 2
        WHEN 'cced' THEN 3
        WHEN 'bcced' THEN 4
    END,
    email
)

select * from final