{{ config(materialized='table') }}

{#
  Nexus Metrics Metadata — one row per metric in the org's semantic layer.

  Source priority:
    1. Warehouse: if var('nexus').sources.semantic_layers.enabled = true, read
       from the BBP-projected `semantic_layers` collection (the new path).
    2. Vars: fall back to var('nexus').metrics (legacy dbt-variables approach,
       present during transition; remove from client dbt_project.yml after
       verifying warehouse data matches).
    3. Empty: no metrics configured → type-safe zero-row result.
#}

{% set use_warehouse = var('nexus', {}).get('sources', {}).get('semantic_layers', {}).get('enabled', false) %}
{% set all_metrics = var('nexus', {}).get('metrics', {}) %}
{% set has_metrics = all_metrics | length > 0 %}

{% if use_warehouse %}

-- ── Warehouse path ────────────────────────────────────────────────────────────
-- Read the latest semantic layer row per (organization_id, layer_slug) and
-- unnest the metrics array. Adapter-portable (BigQuery JSON vs Snowflake VARIANT).

with latest as (
    select _raw_record, _ingested_at
    from {{ source('semantic_layers', 'semantic_layers') }}
    qualify row_number() over (
        partition by
        {% if target.type == 'bigquery' %}
            json_value(_raw_record, '$.organization_id'),
            json_value(_raw_record, '$.layer_slug')
        {% else %}
            _raw_record:organization_id::string,
            _raw_record:layer_slug::string
        {% endif %}
        order by _ingested_at desc
    ) = 1
)

{% if target.type == 'bigquery' %}
select
    json_value(m, '$.model') as model,
    json_value(m, '$.name') as metric_name,
    json_value(m, '$.label') as label,
    nullif(
        array_to_string(
            array(select json_value(x) from unnest(json_query_array(m, '$.aliases')) as x),
            ', '
        ), ''
    ) as aliases,
    json_value(m, '$.type') as metric_type,
    nullif(
        array_to_string(
            array(select json_value(x) from unnest(json_query_array(m, '$.tables')) as x),
            ', '
        ), ''
    ) as tables,
    json_value(m, '$.metric_sql') as metric_sql,
    nullif(
        array_to_string(
            array(select json_value(x) from unnest(json_query_array(m, '$.filter')) as x),
            ' AND '
        ), ''
    ) as filter,
    json_value(m, '$.format') as format,
    json_value(m, '$.unit') as unit,
    json_value(m, '$.polarity') as polarity,
    cast(json_value(m, '$.precision') as int64) as precision,
    nullif(
        array_to_string(
            array(select json_value(x) from unnest(json_query_array(m, '$.tags')) as x),
            ', '
        ), ''
    ) as tags,
    json_value(m, '$.description') as description,
    nullif(
        array_to_string(
            array(select json_value(x) from unnest(json_query_array(m, '$.example_questions')) as x),
            '; '
        ), ''
    ) as example_questions
from latest,
     unnest(json_query_array(_raw_record, '$.layer.metrics')) as m

{% else %}

select
    m.value:model::string as model,
    m.value:name::string as metric_name,
    m.value:label::string as label,
    nullif(array_to_string(m.value:aliases::array, ', '), '') as aliases,
    m.value:type::string as metric_type,
    nullif(array_to_string(m.value:tables::array, ', '), '') as tables,
    m.value:metric_sql::string as metric_sql,
    nullif(array_to_string(m.value:filter::array, ' AND '), '') as filter,
    m.value:format::string as format,
    m.value:unit::string as unit,
    m.value:polarity::string as polarity,
    m.value:precision::integer as precision,
    nullif(array_to_string(m.value:tags::array, ', '), '') as tags,
    m.value:description::string as description,
    nullif(array_to_string(m.value:example_questions::array, '; '), '') as example_questions
from latest,
     lateral flatten(input => _raw_record:layer:metrics) m

{% endif %}

{% elif has_metrics %}

-- ── Legacy vars path ──────────────────────────────────────────────────────────
-- Present during transition while client dbt_project.yml vars still exist.
-- Remove vars (and this branch becomes unreachable) after verifying warehouse data.

    {% set ns = namespace(first=true) %}
    {% for model_name, metrics_list in all_metrics.items() %}
        {% for metric in metrics_list %}
            {% if not ns.first %}UNION ALL{% endif %}
            {% set ns.first = false %}
            SELECT
                {{ nexus.metrics_metadata_sql_str(model_name) }} AS model,
                {{ nexus.metrics_metadata_sql_str(metric.name) }} AS metric_name,
                {{ nexus.metrics_metadata_sql_str(metric.get("label", metric.name)) }} AS label,
                {% if metric.get('aliases') %}{{ nexus.metrics_metadata_sql_str(metric.aliases | join(", ")) }}{% else %}NULL{% endif %} AS aliases,
                {{ nexus.metrics_metadata_sql_str(metric.type) }} AS metric_type,
                {% if metric.get('tables') %}{{ nexus.metrics_metadata_sql_str(metric.tables | join(", ")) }}{% else %}NULL{% endif %} AS tables,
                {{ nexus.metrics_metadata_sql_str(metric.metric_sql | trim) }} AS metric_sql,
                {% if metric.get('filter') %}{{ nexus.metrics_metadata_sql_str(metric.filter | join(" AND ")) }}{% else %}NULL{% endif %} AS filter,
                {% if metric.get('format') %}{{ nexus.metrics_metadata_sql_str(metric.format) }}{% else %}NULL{% endif %} AS format,
                {% if metric.get('unit') %}{{ nexus.metrics_metadata_sql_str(metric.unit) }}{% else %}NULL{% endif %} AS unit,
                {% if metric.get('polarity') %}{{ nexus.metrics_metadata_sql_str(metric.polarity) }}{% else %}NULL{% endif %} AS polarity,
                {{ metric.precision if metric.get('precision') is not none else 'NULL' }} AS precision,
                {% if metric.get('tags') %}{{ nexus.metrics_metadata_sql_str(metric.tags | join(", ")) }}{% else %}NULL{% endif %} AS tags,
                {{ nexus.metrics_metadata_sql_str(metric.get("description", "") | trim) }} AS description,
                {% if metric.get('example_questions') %}{{ nexus.metrics_metadata_sql_str(metric.example_questions | join("; ")) }}{% else %}NULL{% endif %} AS example_questions
        {% endfor %}
    {% endfor %}

{% else %}

-- ── Empty result ──────────────────────────────────────────────────────────────
    {% if target.type == 'bigquery' %}
    SELECT
        CAST(NULL AS STRING) AS model,
        CAST(NULL AS STRING) AS metric_name,
        CAST(NULL AS STRING) AS label,
        CAST(NULL AS STRING) AS aliases,
        CAST(NULL AS STRING) AS metric_type,
        CAST(NULL AS STRING) AS tables,
        CAST(NULL AS STRING) AS metric_sql,
        CAST(NULL AS STRING) AS filter,
        CAST(NULL AS STRING) AS format,
        CAST(NULL AS STRING) AS unit,
        CAST(NULL AS STRING) AS polarity,
        CAST(NULL AS INT64) AS precision,
        CAST(NULL AS STRING) AS tags,
        CAST(NULL AS STRING) AS description,
        CAST(NULL AS STRING) AS example_questions
    LIMIT 0
    {% else %}
    SELECT
        CAST(NULL AS VARCHAR) AS model,
        CAST(NULL AS VARCHAR) AS metric_name,
        CAST(NULL AS VARCHAR) AS label,
        CAST(NULL AS VARCHAR) AS aliases,
        CAST(NULL AS VARCHAR) AS metric_type,
        CAST(NULL AS VARCHAR) AS tables,
        CAST(NULL AS VARCHAR) AS metric_sql,
        CAST(NULL AS VARCHAR) AS filter,
        CAST(NULL AS VARCHAR) AS format,
        CAST(NULL AS VARCHAR) AS unit,
        CAST(NULL AS VARCHAR) AS polarity,
        CAST(NULL AS INTEGER) AS precision,
        CAST(NULL AS VARCHAR) AS tags,
        CAST(NULL AS VARCHAR) AS description,
        CAST(NULL AS VARCHAR) AS example_questions
    WHERE 1 = 0
    {% endif %}

{% endif %}
