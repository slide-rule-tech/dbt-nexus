{% macro nexus_bq_partition_by(field, granularity='day', data_type='timestamp') %}
  {# Returns a dbt partition_by={...} dict for BigQuery when warehouse
     optimization is enabled AND the current target is BigQuery.
     Returns none otherwise — dbt treats partition_by=none as no
     partitioning, so this is a clean no-op for Snowflake and other
     adapters.

     Usage in a model config:
       {{ config(
           materialized='table',
           partition_by=nexus.nexus_bq_partition_by('occurred_at'),
           ...
       ) }}
  #}
  {%- if nexus.nexus_warehouse_optimization_enabled() and target.type == 'bigquery' -%}
    {%- do return({'field': field, 'data_type': data_type, 'granularity': granularity}) -%}
  {%- else -%}
    {%- do return(none) -%}
  {%- endif -%}
{% endmacro %}
