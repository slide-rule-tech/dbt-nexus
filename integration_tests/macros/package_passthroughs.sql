{# dbt macro name resolution is dynamically scoped: a macro body resolves
   unqualified names through the CALLING node's context. The package's
   resolver macros call `create_nexus_id(...)` unqualified, which works from
   models inside the package (package-local namespace) but not from this
   project's shadow models (root namespace). Root-project macros are visible
   from every context, so this passthrough bridges the gap. #}
{% macro create_nexus_id(type, cols) %}
  {{ return(nexus.create_nexus_id(type, cols)) }}
{% endmacro %}
