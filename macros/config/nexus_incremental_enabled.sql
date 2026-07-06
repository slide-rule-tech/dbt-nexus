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
