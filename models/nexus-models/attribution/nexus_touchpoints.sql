{{ config(materialized = 'table', tags=['attribution']) }}

{%- set sources = var('sources', []) -%}
{% set relations_to_union = [] %}
{% for source in sources %}
    {% if source.attribution %}
        {% do relations_to_union.append(ref(source.name ~ '_touchpoints')) %}
    {% endif %}
{% endfor %}

{% if relations_to_union %}
    {{ dbt_utils.union_relations(
        relations=relations_to_union
    ) }}
{% else %}
-- Return empty result when no touchpoint sources are configured
WITH empty_result AS (
    SELECT
        {{ common_touchpoint_fields(return_empty=true) }}
)

SELECT 
    {{ common_touchpoint_fields() }}
FROM empty_result
WHERE 1 = 0
{% endif %}
