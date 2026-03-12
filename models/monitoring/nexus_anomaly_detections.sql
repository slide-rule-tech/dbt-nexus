{{ config(materialized='table', tags=['monitoring']) }}

{% set relations_to_union = [] %}
{% set nexus_config = var('nexus', {}) %}
{% set anomalies_config = nexus_config.get('anomalies', {}) %}

{% for monitor_name, monitor_config in anomalies_config.items() %}
    {% if monitor_config.get('enabled', false) %}
        {% do relations_to_union.append(ref('anomalies_' ~ monitor_name)) %}
    {% endif %}
{% endfor %}

{% if relations_to_union %}
    {{ dbt_utils.union_relations(relations=relations_to_union) }}
{% else %}
SELECT
    cast(null as varchar) as detection_id,
    cast(null as varchar) as monitor_name,
    cast(null as timestamp) as detected_at,
    cast(null as varchar) as dimension_key,
    cast(null as timestamp) as occurred_at,
    cast(null as varchar) as granularity,
    {% if target.type == 'snowflake' %}
    parse_json('{}') as dimensions,
    parse_json('{}') as measures,
    parse_json('{}') as z_scores,
    {% else %}
    cast(null as json) as dimensions,
    cast(null as json) as measures,
    cast(null as json) as z_scores,
    {% endif %}
    cast(null as number) as max_abs_z
WHERE 1 = 0
{% endif %}
