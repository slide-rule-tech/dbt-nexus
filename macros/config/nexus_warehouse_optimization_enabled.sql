{% macro nexus_warehouse_optimization_enabled() %}
  {# Returns true when the warehouse-optimization toggles (partition_by,
     cluster_by on the core nexus_* models) should be applied.

     Controlled by:
       vars:
         nexus:
           warehouse_optimization:
             enabled: null | true | false

     - null / unset: auto mode — on for BigQuery only. Snowflake gets
       no-ops because Snowflake clustering is billed background work
       and we don't want to enable it by default.
     - true: force on. A Snowflake user opting in here gets cluster_by
       on the core models (no partition_by, which is BQ-specific and
       returns none on Snowflake anyway).
     - false: force off. A BigQuery user opts out here.
  #}
  {%- set cfg = var('nexus', {}).get('warehouse_optimization', {}) -%}
  {%- set explicit = cfg.get('enabled') -%}
  {%- if explicit is not none -%}
    {%- do return(explicit) -%}
  {%- else -%}
    {%- do return(target.type == 'bigquery') -%}
  {%- endif -%}
{% endmacro %}
