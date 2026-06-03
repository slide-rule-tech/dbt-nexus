{% macro nexus_cluster_by(keys) %}
  {# Returns the cluster_by keys list when warehouse optimization is
     enabled; otherwise none (dbt no-op).

     Works on both BigQuery (free, query-time block pruning) and
     Snowflake (paid auto-clustering). Default-off on Snowflake via
     nexus_warehouse_optimization_enabled — a Snowflake operator must
     explicitly opt in.

     Usage:
       {{ config(
           materialized='table',
           cluster_by=nexus.nexus_cluster_by(['event_name', 'source']),
           ...
       ) }}
  #}
  {%- if nexus.nexus_warehouse_optimization_enabled() -%}
    {%- do return(keys) -%}
  {%- else -%}
    {%- do return(none) -%}
  {%- endif -%}
{% endmacro %}
