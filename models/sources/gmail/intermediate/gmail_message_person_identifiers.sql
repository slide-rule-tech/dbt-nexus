{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['entity_identifier_id']),
    unique_key='entity_identifier_id',
    on_schema_change='append_new_columns',
    tags=['gmail', 'intermediate', 'person_identifiers']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'entity_identifier_id']) }}

-- Extract person identifiers from gmail message participants
WITH participants AS (
    SELECT * FROM {{ ref('gmail_message_participants') }}
    {% if is_incremental() %}
    WHERE _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
    {% endif %}
),

participants_with_event_id AS (
    SELECT 
        {{ nexus.create_nexus_id('event', ['message_id']) }} as event_id,
        message_id,
        email,
        sent_at,
        _ingested_at,
        role
    FROM participants
    WHERE email IS NOT NULL
),

identifiers AS (
    SELECT 
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'email', "'person'", 'role']) }} as entity_identifier_id,
        event_id,
        {{ nexus.create_nexus_id('edge', ['event_id', 'email', "'person'", 'role']) }} as edge_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at,
        role
    FROM participants_with_event_id
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
    FROM identifiers
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
