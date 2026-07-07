{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['relationship_declaration_id']),
    unique_key='relationship_declaration_id',
    on_schema_change='append_new_columns',
    tags=['gmail', 'intermediate', 'relationship_declarations']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'relationship_declaration_id']) }}

-- Extract person→group relationships from gmail message participants
WITH participants AS (
    SELECT * FROM {{ ref('gmail_message_participants') }}
    {% if is_incremental() %}
    WHERE _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
    {% endif %}
),

-- Extract participants with valid email and domain (filter generic domains)
participants_with_domains AS (
    SELECT
        {{ nexus.create_nexus_id('event', ['message_id']) }} as event_id,
        sent_at,
        _ingested_at,
        email as entity_a_identifier,
        domain as entity_b_identifier,
        role
    FROM participants
    WHERE email IS NOT NULL
      AND domain IS NOT NULL
      AND {{ filter_non_generic_domains('domain') }}
      AND domain NOT LIKE '%>%'
),

-- Create relationships
relationships AS (
    SELECT DISTINCT
        event_id,
        sent_at as occurred_at,
        entity_a_identifier,
        'email' as entity_a_identifier_type,
        'person' as entity_a_type,
        'member' as entity_a_role,
        entity_b_identifier,
        'domain' as entity_b_identifier_type,
        'group' as entity_b_type,
        'organization' as entity_b_role,
        'membership' as relationship_type,
        'a_to_b' as relationship_direction,
        true as is_active,
        'gmail' as source,
        _ingested_at
    FROM participants_with_domains
),

relationships_with_ids AS (
    SELECT
        {{ nexus.create_nexus_id('relationship_declaration', ['event_id', 'entity_a_identifier', 'entity_b_identifier', 'entity_a_role', 'occurred_at']) }} as relationship_declaration_id,
        event_id,
        occurred_at,
        entity_a_identifier,
        entity_a_identifier_type,
        entity_a_type,
        entity_a_role,
        entity_b_identifier,
        entity_b_identifier_type,
        entity_b_type,
        entity_b_role,
        relationship_type,
        relationship_direction,
        is_active,
        source,
        _ingested_at
    FROM relationships
),

-- Deduplicate: same relationship_declaration_id can appear from multiple streams/ingestions
-- Keep the row with the most recent _ingested_at
deduplicated_relationships AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY relationship_declaration_id 
            ORDER BY _ingested_at DESC
        ) as rn
    FROM relationships_with_ids
)

SELECT
    relationship_declaration_id,
    event_id,
    occurred_at,
    entity_a_identifier,
    entity_a_identifier_type,
    entity_a_type,
    entity_a_role,
    entity_b_identifier,
    entity_b_identifier_type,
    entity_b_type,
    entity_b_role,
    relationship_type,
    relationship_direction,
    is_active,
    source,
    _ingested_at
FROM deduplicated_relationships
WHERE rn = 1
