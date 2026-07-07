{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['entity_identifier_id']),
    unique_key='entity_identifier_id',
    on_schema_change='append_new_columns',
    tags=['nexus', 'google_calendar', 'intermediate', 'group_identifiers']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'entity_identifier_id']) }}

-- Extract group (domain) identifiers from google calendar event participants
WITH participants AS (
    SELECT * FROM {{ ref('google_calendar_event_participants') }}
    {% if is_incremental() %}
    WHERE _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
    {% endif %}
),

participants_with_nexus_event_id AS (
    SELECT
        {{ nexus.create_nexus_id('event', ['event_id']) }} as nexus_event_id,
        event_id,
        instance_start,
        _ingested_at,
        domain,
        role
    FROM participants
),

-- Filter out generic domains
domains_filtered AS (
    SELECT DISTINCT
        nexus_event_id,
        event_id,
        instance_start,
        _ingested_at,
        domain,
        role
    FROM participants_with_nexus_event_id
    WHERE {{ filter_non_generic_domains('domain') }}
      AND domain NOT LIKE '%>%'
),

-- Create domain identifiers
domain_identifiers AS (
    SELECT
        {{ nexus.create_nexus_id('entity_identifier', ['nexus_event_id', 'domain', "'group'", 'role', 'instance_start']) }} as entity_identifier_id,
        nexus_event_id as event_id,
        {{ nexus.create_nexus_id('edge', ['nexus_event_id', 'domain', "'group'", 'role']) }} as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        domain as identifier_value,
        'google_calendar' as source,
        instance_start as occurred_at,
        _ingested_at,
        role
    FROM domains_filtered
    WHERE domain IS NOT NULL
),

-- Add redirected domains (www. versions)
redirected_domains AS (
    SELECT
        {{ nexus.create_nexus_id('entity_identifier', ['nexus_event_id', nexus.redirected_domain('domain'), "'group'", 'role', 'instance_start']) }} as entity_identifier_id,
        nexus_event_id as event_id,
        {{ nexus.create_nexus_id('edge', ['nexus_event_id', nexus.redirected_domain('domain'), "'group'", 'role']) }} as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        {{ nexus.redirected_domain('domain') }} as identifier_value,
        'google_calendar' as source,
        instance_start as occurred_at,
        _ingested_at,
        role
    FROM domains_filtered
    WHERE domain IS NOT NULL
)

SELECT * FROM domain_identifiers
UNION ALL
SELECT * FROM redirected_domains
