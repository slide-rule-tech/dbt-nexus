{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['entity_trait_id']),
    unique_key='entity_trait_id',
    on_schema_change='append_new_columns',
    tags=['gmail', 'intermediate', 'person_traits']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'entity_trait_id']) }}

-- Extract person traits from gmail message participants
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
        name,
        sent_at,
        _ingested_at,
        role
    FROM participants
),

name_traits AS (
    -- Person name trait
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'name'", 'role']) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'name' as trait_name,
        name as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    FROM participants_with_event_id
    WHERE name IS NOT NULL

    UNION ALL

    -- Person email trait
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'email', "'person'", "'email'", 'role']) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'email' as trait_name,
        email as trait_value,
        'gmail' as source,
        sent_at as occurred_at,
        _ingested_at
    FROM participants_with_event_id
    WHERE email IS NOT NULL
),

-- Deduplicate: same entity_trait_id can appear from multiple streams/ingestions
-- Keep the row with the most recent _ingested_at
deduplicated_traits AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY entity_trait_id 
            ORDER BY _ingested_at DESC
        ) as rn
    FROM name_traits
)

SELECT 
    entity_trait_id,
    event_id,
    entity_type,
    identifier_type,
    identifier_value,
    trait_name,
    trait_value,
    source,
    occurred_at,
    _ingested_at
FROM deduplicated_traits
WHERE rn = 1
