{{ config(
    materialized='table',
    partition_by=nexus.nexus_bq_partition_by('occurred_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['event_name', 'source']),
    post_hook=nexus.nexus_bq_informational_constraints(primary_key='event_id'),
) }}

{# Monthly (not daily) partitioning on occurred_at: event history in
   real tenants commonly spans more than the 4000-partition BigQuery
   cap when partitioned daily (e.g. AWM exceeds 4000 days). Monthly
   gives 4000 / 12 ≈ 333 years of headroom; a 90-day query still
   prunes to ~4 monthly partitions ≈ 120 days scanned, negligibly
   worse than the 90-day exact scan daily would give. #}

{# Collect relations to union based on sources with events #}
{% set relations_to_union = [] %}

{# Support both new and legacy config patterns #}
{% set nexus_config = var('nexus', {}) %}
{% set sources_config = nexus_config.get('sources', {}) %}

{% if sources_config %}
    {# New pattern: nexus.sources dictionary #}
    {% for source_name, source_config in sources_config.items() %}
        {% if source_config.get('enabled') and source_config.get('events') %}
            {% do relations_to_union.append(ref(source_name ~ '_events')) %}
        {% endif %}
    {% endfor %}
{% elif var('sources', none) %}
    {# Legacy pattern: sources list #}
    {% for source in var('sources') %}
        {% if source.get('events') %}
            {% do relations_to_union.append(ref(source.name ~ '_events')) %}
        {% endif %}
    {% endfor %}
{% endif %}

{# Set column override based on database type #}
{% if target.type == 'snowflake' %}
    {% set column_overrides = {
        'EVENT_ID': dbt.type_string(),
        'OCCURRED_AT': dbt.type_timestamp(),
        'EVENT_NAME': dbt.type_string(),
        'EVENT_DESCRIPTION': dbt.type_string(),
        'EVENT_TYPE': dbt.type_string(),
        'SIGNIFICANCE': dbt.type_float(),
        'SOURCE': dbt.type_string(),
        'SOURCE_TABLE': dbt.type_string(),
        '_INGESTED_AT': dbt.type_timestamp(),
        '_PROCESSED_AT': dbt.type_timestamp()
    } %}
{% else %}
    {% set column_overrides = {
        'event_id': dbt.type_string(),
        'occurred_at': dbt.type_timestamp(),
        'event_name': dbt.type_string(),
        'event_description': dbt.type_string(),
        'event_type': dbt.type_string(),
        'significance': dbt.type_float(),
        'source': dbt.type_string(),
        'source_table': dbt.type_string(),
        '_ingested_at': dbt.type_timestamp(),
        '_processed_at': dbt.type_timestamp()
    } %}
{% endif %}

{# Define desired columns with their types #}
{% set desired_columns = [
    {'name': 'event_id', 'type': 'string'},
    {'name': 'occurred_at', 'type': 'timestamp'},
    {'name': 'event_name', 'type': 'string'},
    {'name': 'event_description', 'type': 'string'},
    {'name': 'event_type', 'type': 'string'},
    {'name': 'significance', 'type': 'float'},
    {'name': 'source', 'type': 'string'},
    {'name': 'source_table', 'type': 'string'},
    {'name': '_ingested_at', 'type': 'timestamp'},
    {'name': '_processed_at', 'type': 'timestamp'}
] %}

{# Get all columns from all relations to check what exists #}
{% set all_columns = {} %}
{% for relation in relations_to_union %}
    {% set cols = adapter.get_columns_in_relation(relation) %}
    {% for col in cols %}
        {% do all_columns.update({col.column.lower(): col.column}) %}
    {% endfor %}
{% endfor %}

{# Build the final column list for union_relations #}
{% set available_columns = [] %}
{% set final_column_overrides = {} %}

{% for desired_col in desired_columns %}
    {% if desired_col.name.lower() in all_columns %}
        {% do available_columns.append(desired_col.name) %}
        {# Add to column overrides based on database type #}
        {% if target.type == 'snowflake' %}
            {% set col_key = all_columns[desired_col.name.lower()] %}
        {% else %}
            {% set col_key = desired_col.name.lower() %}
        {% endif %}
        
        {% if desired_col.type == 'float' %}
            {% do final_column_overrides.update({col_key: dbt.type_float()}) %}
        {% elif desired_col.type == 'timestamp' %}
            {% do final_column_overrides.update({col_key: dbt.type_timestamp()}) %}
        {% else %}
            {% do final_column_overrides.update({col_key: dbt.type_string()}) %}
        {% endif %}
    {% endif %}
{% endfor %}

WITH unioned AS (
    {{ dbt_utils.union_relations(
        relations=relations_to_union,
        include=available_columns,
        column_override=final_column_overrides
    ) }}
)

SELECT
    {# Select available columns and add NULLs for missing ones #}
    {% set processed_columns = [] %}
    {% for desired_col in desired_columns -%}
        {% if desired_col.name != '_processed_at' %}
            {% if desired_col.name.lower() in all_columns %}
                {% do processed_columns.append(desired_col.name.lower()) %}
            {% else %}
                {% if desired_col.type == 'float' %}
                    {% do processed_columns.append('CAST(NULL AS ' ~ dbt.type_float() ~ ') AS ' ~ desired_col.name.lower()) %}
                {% elif desired_col.type == 'timestamp' %}
                    {% do processed_columns.append('CAST(NULL AS ' ~ dbt.type_timestamp() ~ ') AS ' ~ desired_col.name.lower()) %}
                {% else %}
                    {% do processed_columns.append('CAST(NULL AS ' ~ dbt.type_string() ~ ') AS ' ~ desired_col.name.lower()) %}
                {% endif %}
            {% endif %}
        {% endif %}
    {% endfor %}
    {{ processed_columns | join(',\n    ') }},
    current_timestamp() as _processed_at
FROM unioned
{# BigQuery rejects `ORDER BY` in a CTAS that uses `partition_by`.
   The ORDER BY at write time was never load-bearing for downstream
   consumers — BigQuery and Snowflake both re-sort at read time when
   needed — so we drop it whenever partitioning is on. Without
   partitioning, preserve the historical ordering hint. #}
{% if not (nexus.nexus_warehouse_optimization_enabled() and target.type == 'bigquery') %}
ORDER BY occurred_at DESC
{% endif %}