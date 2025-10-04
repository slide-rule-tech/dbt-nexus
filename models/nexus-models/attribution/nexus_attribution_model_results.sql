{{ config(materialized = 'table', tags=['attribution']) }}

{# Collect relations to union based on nexus attribution_models configuration #}
{% set relations_to_union = [] %}
{% set attribution_models = var('nexus', {}).get('attribution_models', {}) %}
{% for model_name, model_config in attribution_models.items() %}
    {% if model_config.get('enabled', false) %}
        {% do relations_to_union.append(ref(model_name)) %}
    {% endif %}
{% endfor %}

{% if relations_to_union %}
    {{ dbt_utils.union_relations(
        relations=relations_to_union
    ) }}
{% else %}
-- Return empty result when no attribution models are configured
WITH empty_result AS (
    SELECT
        {{ common_attribution_model_result_fields(return_empty=true) }}
)

SELECT 
    {{ common_attribution_model_result_fields() }}
FROM empty_result
WHERE 1 = 0
{% endif %}
