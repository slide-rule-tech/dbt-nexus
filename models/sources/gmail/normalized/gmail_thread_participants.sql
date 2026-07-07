{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['thread_id']),
    unique_key=['thread_id', 'email'],
    on_schema_change='append_new_columns',
    tags=['gmail', 'normalized']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_watermark_ingested_at', 'thread_id']) }}

{% if is_incremental() %}
{% set wm = nexus.nexus_incremental_watermark_literal('_watermark_ingested_at') %}
{% endif %}

-- Cross-account normalized thread participants: Group per-account participants by first_message_id_header
--
-- Touched-group rollup. Child clocks = both upstream rollups'
-- _watermark_ingested_at (their _ingested_at is a frozen MIN); a touched
-- thread re-derives ALL its participants. Same first_message_id_header
-- re-key caveat as gmail_threads (stale old-key rows heal on full refresh).
WITH per_account_participants AS (
    SELECT * FROM {{ ref('gmail_thread_participants_by_account') }}
),

per_account_threads AS (
    SELECT * FROM {{ ref('gmail_threads_by_account') }}
),

{% if is_incremental() %}
touched_thread_keys AS (
    SELECT DISTINCT pat.first_message_id_header
    FROM per_account_threads pat
    INNER JOIN per_account_participants pap
        ON pap.gmail_thread_id = pat.gmail_thread_id
        AND pap._account = pat._account
    WHERE pap._watermark_ingested_at > {{ wm }}
      AND pat.first_message_id_header IS NOT NULL
    UNION DISTINCT
    SELECT DISTINCT first_message_id_header
    FROM per_account_threads
    WHERE _watermark_ingested_at > {{ wm }}
      AND first_message_id_header IS NOT NULL
),
{% endif %}

participants_with_thread_id AS (
    SELECT 
        pat.first_message_id_header as thread_id,
        pap.email,
        pap.name,
        pap.participant_raw,
        pap.domain,
        pap.roles,
        pap.first_participated_at,
        pap.last_participated_at,
        pap._ingested_at,
        GREATEST(pap._watermark_ingested_at, pat._watermark_ingested_at) as _watermark_ingested_at
    FROM per_account_participants pap
    INNER JOIN per_account_threads pat
        ON pap.gmail_thread_id = pat.gmail_thread_id
        AND pap._account = pat._account
    {% if is_incremental() %}
    INNER JOIN touched_thread_keys tk ON pat.first_message_id_header = tk.first_message_id_header
    {% endif %}
    WHERE pat.first_message_id_header IS NOT NULL
),

thread_participants AS (
    SELECT
        thread_id,
        email,
        {% if target.type == 'bigquery' %}ARRAY_AGG(name ORDER BY first_participated_at ASC LIMIT 1)[OFFSET(0)]{% else %}first(name ORDER BY first_participated_at ASC){% endif %} as name,
        {% if target.type == 'bigquery' %}ARRAY_AGG(participant_raw ORDER BY first_participated_at ASC LIMIT 1)[OFFSET(0)]{% else %}first(participant_raw ORDER BY first_participated_at ASC){% endif %} as participant_raw,
        domain,
        {% if target.type == 'bigquery' %}ARRAY_CONCAT_AGG(roles){% else %}flatten(array_agg(roles)){% endif %} as roles_raw,
        MIN(first_participated_at) as first_participated_at,
        MAX(last_participated_at) as last_participated_at,
        MIN(_ingested_at) as _ingested_at,
        MAX(_watermark_ingested_at) as _watermark_ingested_at
    FROM participants_with_thread_id
    GROUP BY thread_id, email, domain
),

final as (

SELECT 
    thread_id,
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
    ) as roles,
    first_participated_at,
    last_participated_at,
    _ingested_at,
    _watermark_ingested_at
FROM thread_participants
ORDER BY thread_id, 
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