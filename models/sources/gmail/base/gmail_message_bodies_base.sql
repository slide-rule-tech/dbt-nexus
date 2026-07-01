{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('bodies', false),
    materialized='view',
    tags=['gmail', 'base', 'bodies']
) }}

-- Flattens the `gmail_message_bodies` Big Beautiful Pipeline collection (written
-- by the gmail_message_body enricher, app/convex/enrichment/enrichers) into typed
-- columns. The enricher lands bodies in the org's GMAIL source dataset (same
-- dataset as gmail_messages), on the lean BBP envelope — all fields live in
-- `_raw_record`. Gated on the `gmail.bodies` var so only orgs running the enricher
-- build it. get_relation guard → empty (but typed) until the first body is pulled,
-- so gmail_message_events' join stays safe.

{% set gmail_schema = var('nexus', {}).get('sources', {}).get('gmail', {}).get('schema', 'gmail') %}
{% set bodies_rel = adapter.get_relation(
    database=target.database,
    schema=gmail_schema,
    identifier='gmail_message_bodies',
) %}

{% if bodies_rel is none %}

SELECT
    CAST(NULL AS {{ dbt.type_string() }}) AS message_id_header,
    CAST(NULL AS {{ dbt.type_string() }}) AS gmail_account_email,
    CAST(NULL AS {{ dbt.type_string() }}) AS gmail_account_message_id,
    CAST(NULL AS {{ dbt.type_string() }}) AS body_plain,
    CAST(NULL AS {{ dbt.type_string() }}) AS body_html,
    CAST(NULL AS {{ dbt.type_string() }}) AS body_text_from_html,
    CAST(NULL AS {{ dbt.type_bigint() }}) AS body_size_bytes,
    CAST(NULL AS {{ dbt.type_bigint() }}) AS body_truncated_at_bytes,
    CAST(NULL AS {{ dbt.type_timestamp() }}) AS fetched_at,
    CAST(NULL AS {{ dbt.type_timestamp() }}) AS _queued_at
FROM (SELECT 1) _
WHERE FALSE

{% else %}

SELECT
    {{ nexus.json_path('_raw_record', 'message_id_header', 'string') }} AS message_id_header,
    {{ nexus.json_path('_raw_record', 'gmail_account_email', 'string') }} AS gmail_account_email,
    {{ nexus.json_path('_raw_record', 'gmail_account_message_id', 'string') }} AS gmail_account_message_id,
    {{ nexus.json_path('_raw_record', 'body_plain', 'string') }} AS body_plain,
    {{ nexus.json_path('_raw_record', 'body_html', 'string') }} AS body_html,
    {{ nexus.json_path('_raw_record', 'body_text_from_html', 'string') }} AS body_text_from_html,
    {{ nexus.json_path('_raw_record', 'body_size_bytes', 'bigint') }} AS body_size_bytes,
    {{ nexus.json_path('_raw_record', 'body_truncated_at_bytes', 'bigint') }} AS body_truncated_at_bytes,
    {{ nexus.json_path('_raw_record', 'fetched_at', 'timestamp') }} AS fetched_at,
    _queued_at
FROM {{ bodies_rel }}

{% endif %}
