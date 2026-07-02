{# Feature flag for incremental identity resolution.

    Consumers opt in via:

        vars:
          nexus:
            incremental:
              enabled: true

    Defaults to false: every model behaves exactly as before (full
    rebuild as `table`). See docs/incremental-identity-resolution.md
    for the design and the semantic changes that come with enabling it
    (most importantly: entity ids become stable-across-runs rather than
    content-derived, and merges are recorded in nexus_resolution_log).
#}
{% macro nexus_incremental_enabled() %}
  {{ return(var('nexus', {}).get('incremental', {}).get('enabled', false)) }}
{% endmacro %}

{# Materialization helper: incremental when the flag is on, otherwise the
   existing default. Used in model config() blocks so the same model file
   serves both modes. #}
{% macro nexus_incremental_materialization(default='table') %}
  {%- if nexus.nexus_incremental_enabled() -%}
    {{ return('incremental') }}
  {%- else -%}
    {{ return(default) }}
  {%- endif -%}
{% endmacro %}

{# The standard ingestion-time watermark predicate for incremental source
   models: only rows ingested after this model's own high-water mark. Renders
   nothing outside an incremental run, so models stay valid in table mode.

   Usage (note the subquery wrap -- a bare WHERE after union_relations would
   bind to the union's last branch only):

     select * from (
         {{ dbt_utils.union_relations(relations=[...]) }}
     ) unioned
     {{ nexus.nexus_incremental_source_filter() }}

   The watermark is always ingestion time, never occurred_at -- late-arriving
   events must still enter (docs/incremental-identity-resolution.md §2.6). #}
{% macro nexus_incremental_source_filter(column='_ingested_at') %}
  {%- if is_incremental() %}
where {{ column }} > coalesce(
    (select max({{ column }}) from {{ this }}),
    cast('1970-01-01' as timestamp)
)
  {%- endif %}
{% endmacro %}
