{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['gmail_thread_id', '_account']),
    unique_key=['gmail_thread_id', '_account', 'email'],
    on_schema_change='append_new_columns',
    tags=['gmail', 'normalized', 'by_account']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_watermark_ingested_at', 'gmail_thread_id']) }}

-- Per-account normalized thread participants: Aggregate participants by gmail_thread_id
--
-- Touched-group rollup (see nexus_incremental_touched_groups.sql). The
-- touched-set unions BOTH upstreams' batches: a new participant row touches
-- its thread, and a re-synced message can change thread linkage.
WITH messages AS (
    SELECT * FROM {{ ref('gmail_messages_by_account') }}
),

participants AS (
    SELECT * FROM {{ ref('gmail_message_participants_by_account') }}
),

{% if is_incremental() %}
touched_threads AS (
    SELECT DISTINCT m.gmail_thread_id, m._account
    FROM messages m
    INNER JOIN participants p
        ON p.gmail_message_id = m.gmail_message_id
        AND p._account = m._account
    WHERE p._ingested_at > {{ nexus.nexus_incremental_watermark_literal('_watermark_ingested_at') }}
    UNION DISTINCT
    SELECT DISTINCT gmail_thread_id, _account
    FROM messages
    WHERE _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_watermark_ingested_at') }}
),
{% endif %}

participants_with_threads AS (
    SELECT 
        p.gmail_message_id,
        p.email,
        p.name,
        p.participant_raw,
        p.domain,
        p.role,
        p.sent_at,
        p._ingested_at,
        p._account,
        m.gmail_thread_id
    FROM participants p
    INNER JOIN messages m 
        ON p.gmail_message_id = m.gmail_message_id 
        AND p._account = m._account
    {% if is_incremental() %}
    INNER JOIN touched_threads tt
    {{ nexus.nexus_incremental_touched_join('m', 'tt', ['gmail_thread_id', '_account']) }}
    {% endif %}
    WHERE m.gmail_thread_id IS NOT NULL
      AND p.email IS NOT NULL
),

thread_participants AS (
    SELECT
        gmail_thread_id,
        _account,
        email,
        {% if target.type == 'bigquery' %}ARRAY_AGG(name ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)]{% else %}first(name ORDER BY sent_at ASC){% endif %} as name,
        {% if target.type == 'bigquery' %}ARRAY_AGG(participant_raw ORDER BY sent_at ASC LIMIT 1)[OFFSET(0)]{% else %}first(participant_raw ORDER BY sent_at ASC){% endif %} as participant_raw,
        domain,
        ARRAY_AGG(role) as roles_raw,
        MIN(sent_at) as first_participated_at,
        MAX(sent_at) as last_participated_at,
        MIN(_ingested_at) as _ingested_at,
        MAX(_ingested_at) as _watermark_ingested_at,
    FROM participants_with_threads
    GROUP BY gmail_thread_id, _account, email, domain
),

final as (
SELECT 
    gmail_thread_id,
    _account,
    email,
    name,
    participant_raw,
    domain,
    ARRAY(
        SELECT DISTINCT role 
        FROM UNNEST(roles_raw) as {% if target.type == 'duckdb' %}t(role){% else %}role{% endif %}
        ORDER BY 
            CASE role 
                WHEN 'sender' THEN 1
                WHEN 'recipient' THEN 2
                WHEN 'cced' THEN 3
                WHEN 'bcced' THEN 4
            END
    ) as     roles,
    first_participated_at,
    last_participated_at,
    _ingested_at,
    _watermark_ingested_at
FROM thread_participants
ORDER BY gmail_thread_id, 
    CASE 
        WHEN 'sender' IN (SELECT role FROM UNNEST(roles_raw) as {% if target.type == 'duckdb' %}t(role){% else %}role{% endif %}) THEN 1
        WHEN 'recipient' IN (SELECT role FROM UNNEST(roles_raw) as {% if target.type == 'duckdb' %}t(role){% else %}role{% endif %}) THEN 2
        WHEN 'cced' IN (SELECT role FROM UNNEST(roles_raw) as {% if target.type == 'duckdb' %}t(role){% else %}role{% endif %}) THEN 3
        WHEN 'bcced' IN (SELECT role FROM UNNEST(roles_raw) as {% if target.type == 'duckdb' %}t(role){% else %}role{% endif %}) THEN 4
        ELSE 5
    END,
    first_participated_at ASC,
    email
)

select * from final