{# universal dispatcher #}
{% macro resolve_identifiers(entity_type, identifiers_table, edges_table, max_recursion=10) %}
  {{ return(adapter.dispatch('resolve_identifiers', 'dbt_nexus')(entity_type, identifiers_table, edges_table, max_recursion)) }}
{% endmacro %} 