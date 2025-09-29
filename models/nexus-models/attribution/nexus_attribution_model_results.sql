{{ config(materialized = 'table')}}

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
    {# Return empty result if no attribution models found #}
    select 
        cast(null as string) as attribution_model_result_id,
        cast(null as timestamp) as touchpoint_occurred_at,
        cast(null as string) as attribution_model_name,
        cast(null as string) as touchpoint_batch_id,
        cast(null as string) as touchpoint_event_id,
        cast(null as string) as attributed_event_id,
        cast(null as string) as person_id,
        cast(null as timestamp) as attributed_event_occurred_at
    where 1=0
{% endif %}
