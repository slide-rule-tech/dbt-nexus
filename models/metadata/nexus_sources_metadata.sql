{{ config(materialized='table') }}

-- Nexus Sources Metadata
-- One row per configured source: declarative ingestion metadata (pipeline /
-- connector and the raw field mapped to _ingested_at, from var('nexus').sources)
-- joined to warehouse freshness (MAX(_ingested_at) etc. from nexus_events).
--
-- FULL OUTER JOIN surfaces:
--   * configured sources with no events in the warehouse (is_in_data = false), and
--   * sources present in nexus_events that aren't configured here
--     (is_configured = false) — e.g. a source whose `source` literal doesn't match
--     its config key and has no `ingestion.source_label` override.
--
-- The pipeline / ingested_at_field / source_label come from an optional
-- `ingestion:` block per source in var('nexus').sources:
--   sources:
--     google_ads:
--       events: true
--       ingestion:
--         pipeline: airbyte
--         ingested_at_field: _airbyte_extracted_at
--         source_label: google_ads   # optional; defaults to the dict key

{% set sources_config = var('nexus', {}).get('sources', {}) %}

WITH config_sources AS (
{% if sources_config %}
    {% set ns = namespace(first=true) %}
    {% for source_name, source_config in sources_config.items() %}
        {% set ingestion = source_config.get('ingestion', {}) or {} %}
        {% set source_label = ingestion.get('source_label') or source_name %}
        {% if not ns.first %}UNION ALL{% endif %}
        {% set ns.first = false %}
        SELECT
            {{ nexus.metrics_metadata_sql_str(source_label) }} AS source,
            {{ nexus.metrics_metadata_sql_str(source_name) }} AS config_key,
            {% if ingestion.get('pipeline') %}{{ nexus.metrics_metadata_sql_str(ingestion.get('pipeline')) }}{% else %}NULL{% endif %} AS pipeline,
            {% if ingestion.get('ingested_at_field') %}{{ nexus.metrics_metadata_sql_str(ingestion.get('ingested_at_field')) }}{% else %}NULL{% endif %} AS ingested_at_field,
            {{ 'TRUE' if source_config.get('enabled') else 'FALSE' }} AS enabled,
            {{ 'TRUE' if source_config.get('events') else 'FALSE' }} AS has_events,
            {{ 'TRUE' if source_config.get('dimensions') else 'FALSE' }} AS has_dimensions,
            {{ 'TRUE' if source_config.get('measurements') else 'FALSE' }} AS has_measurements,
            {{ 'TRUE' if source_config.get('entities') else 'FALSE' }} AS has_entities,
            {{ 'TRUE' if source_config.get('attribution') else 'FALSE' }} AS has_attribution
    {% endfor %}
{% else %}
    {% if target.type == 'bigquery' %}
    SELECT
        CAST(NULL AS STRING) AS source,
        CAST(NULL AS STRING) AS config_key,
        CAST(NULL AS STRING) AS pipeline,
        CAST(NULL AS STRING) AS ingested_at_field,
        CAST(NULL AS BOOL) AS enabled,
        CAST(NULL AS BOOL) AS has_events,
        CAST(NULL AS BOOL) AS has_dimensions,
        CAST(NULL AS BOOL) AS has_measurements,
        CAST(NULL AS BOOL) AS has_entities,
        CAST(NULL AS BOOL) AS has_attribution
    LIMIT 0
    {% else %}
    SELECT
        CAST(NULL AS VARCHAR) AS source,
        CAST(NULL AS VARCHAR) AS config_key,
        CAST(NULL AS VARCHAR) AS pipeline,
        CAST(NULL AS VARCHAR) AS ingested_at_field,
        CAST(NULL AS BOOLEAN) AS enabled,
        CAST(NULL AS BOOLEAN) AS has_events,
        CAST(NULL AS BOOLEAN) AS has_dimensions,
        CAST(NULL AS BOOLEAN) AS has_measurements,
        CAST(NULL AS BOOLEAN) AS has_entities,
        CAST(NULL AS BOOLEAN) AS has_attribution
    WHERE 1 = 0
    {% endif %}
{% endif %}
),

warehouse_freshness AS (
    SELECT
        source,
        MAX(_ingested_at) AS last_ingested_at,
        MIN(occurred_at) AS first_event_at,
        MAX(occurred_at) AS last_event_at,
        COUNT(*) AS event_count
    FROM {{ ref('nexus_events') }}
    WHERE source IS NOT NULL
    GROUP BY source
)

SELECT
    COALESCE(c.source, w.source) AS source,
    c.config_key,
    c.pipeline,
    c.ingested_at_field,
    c.enabled,
    c.has_events,
    c.has_dimensions,
    c.has_measurements,
    c.has_entities,
    c.has_attribution,
    w.last_ingested_at,
    w.first_event_at,
    w.last_event_at,
    w.event_count,
    (w.source IS NOT NULL) AS is_in_data,
    (c.config_key IS NOT NULL) AS is_configured
FROM config_sources c
FULL OUTER JOIN warehouse_freshness w
    ON c.source = w.source
ORDER BY w.last_ingested_at DESC NULLS LAST, COALESCE(c.source, w.source)
