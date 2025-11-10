{{ config(materialized='table', tags=['attribution']) }}

{% set relations_to_union = [] %}
{% set nexus_config = var('nexus', {}) %}
{% set sources_config = nexus_config.get('sources', {}) %}

{% for source_name, source_config in sources_config.items() %}
    {% if source_config.get('enabled') and source_config.get('attribution') %}
        {% do relations_to_union.append(ref(source_name ~ '_touchpoints')) %}
    {% endif %}
{% endfor %}

{% if relations_to_union %}
    {{ dbt_utils.union_relations(relations=relations_to_union) }}
{% else %}
WITH empty_result AS (
    SELECT {{ nexus.common_touchpoint_fields(return_empty=true) }}
)
SELECT {{ nexus.common_touchpoint_fields() }}
FROM empty_result
WHERE 1 = 0
{% endif %}
