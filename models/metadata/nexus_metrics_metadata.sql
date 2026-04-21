{{ config(materialized='table') }}

{% set all_metrics = var('nexus', {}).get('metrics', {}) %}

{% set has_metrics = all_metrics | length > 0 %}

{% if has_metrics %}

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
