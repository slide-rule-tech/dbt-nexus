{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['entity_identifier_id']),
    unique_key='entity_identifier_id',
    on_schema_change='append_new_columns',
    tags=['gmail', 'intermediate', 'group_identifiers']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'entity_identifier_id']) }}

-- Extract group (domain) identifiers from gmail message participants
WITH participants AS (
    SELECT * FROM {{ ref('gmail_message_participants') }}
    {% if is_incremental() %}
    WHERE _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
    {% endif %}
),

-- Filter out generic domains
domains_filtered AS (
    SELECT DISTINCT
        {{ nexus.create_nexus_id('event', ['message_id']) }} as event_id,
        sent_at,
        _ingested_at,
        domain,
        role
    FROM participants
    WHERE {{ filter_non_generic_domains('domain') }}
      AND domain NOT LIKE '%>%'
),

-- Create domain identifiers
domain_identifiers AS (
    SELECT
        -- occurred_at (sent_at) is deliberately NOT part of the id. It's a
        -- property of the event, and one logical event (event_id =
        -- hash(message_id)) can arrive from several synced mailboxes with
        -- slightly different sent_at; keying the id on it gave each copy a
        -- distinct id, so the dedup below couldn't collapse them and downstream
        -- entity_participant_id (hash of event_id+entity_id+role) duplicated.
        -- Keyed on the same components as edge_id and the person identifiers.
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'domain', "'group'", 'role']) }} as entity_identifier_id,
        event_id,
        {{ nexus.create_nexus_id('edge', ['event_id', 'domain', "'group'", 'role']) }} as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        domain as identifier_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at,
        role
    FROM domains_filtered
    WHERE domain IS NOT NULL
),

-- Add redirected domains (www. versions)
redirected_domains AS (
    SELECT
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', nexus.redirected_domain('domain'), "'group'", 'role']) }} as entity_identifier_id,
        event_id,
        {{ nexus.create_nexus_id('edge', ['event_id', nexus.redirected_domain('domain'), "'group'", 'role']) }} as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        {{ nexus.redirected_domain('domain') }} as identifier_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at,
        role
    FROM domains_filtered
    WHERE domain IS NOT NULL
),

-- Combine domain and redirected domain identifiers
all_identifiers AS (
    SELECT * FROM domain_identifiers
    UNION ALL
    SELECT * FROM redirected_domains
),

-- Deduplicate: same entity_identifier_id can appear from multiple streams/ingestions
-- Keep the row with the most recent _ingested_at
deduplicated_identifiers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY entity_identifier_id 
            ORDER BY _ingested_at DESC
        ) as rn
    FROM all_identifiers
)

SELECT 
    entity_identifier_id,
    event_id,
    edge_id,
    entity_type,
    identifier_type,
    identifier_value,
    source,
    occurred_at,
    _ingested_at,
    role
FROM deduplicated_identifiers
WHERE rn = 1
