{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['entity_identifier_id']),
    unique_key='entity_identifier_id',
    on_schema_change='append_new_columns',
    tags=['nexus', 'google_calendar', 'intermediate', 'person_identifiers']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'entity_identifier_id']) }}

-- Extract person identifiers from google calendar event participants
WITH participants AS (
    SELECT * FROM {{ ref('google_calendar_event_participants') }}
    {% if is_incremental() %}
    WHERE _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
    {% endif %}
),

participants_with_event_id AS (
    SELECT 
        {{ nexus.create_nexus_id('event', ['event_id']) }} as nexus_event_id,
        event_id,
        email,
        instance_start,
        _ingested_at,
        role
    FROM participants
    WHERE email IS NOT NULL
),

identifiers AS (
    SELECT 
        {{ nexus.create_nexus_id('entity_identifier', ['nexus_event_id', 'email', "'person'", 'role']) }} as entity_identifier_id,
        nexus_event_id as event_id,
        {{ nexus.create_nexus_id('edge', ['nexus_event_id', 'email', "'person'", 'role']) }} as edge_id,
        'person' as entity_type,
        'email' as identifier_type,
        email as identifier_value,
        'google_calendar' as source,
        instance_start as occurred_at,
        _ingested_at,
        role
    FROM participants_with_event_id
),

-- Deduplicate in case same person appears multiple times in same event
deduplicated AS (
    SELECT DISTINCT
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
    FROM identifiers
)

SELECT * FROM deduplicated
WHERE identifier_value IS NOT NULL
