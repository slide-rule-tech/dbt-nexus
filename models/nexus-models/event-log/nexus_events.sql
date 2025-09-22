{{ config(materialized = 'table')}}

{# Collect relations to union based on sources with events #}
{% set relations_to_union = [] %}
{% for source in var('sources') %}
    {% if source.events %}
        {% do relations_to_union.append(ref(source.name ~ '_events')) %}
    {% endif %}
{% endfor %}

WITH unioned AS (
    {{ dbt_utils.union_relations(
        relations=relations_to_union,
        include=[
            'event_id',
            'occurred_at',
            'event_name',
            'event_description',
            'event_type',
            'value',
            'value_unit',
            'significance',
            'source',
            'source_table',
            'synced_at',
        ]
    ) }}
)

SELECT
    *
FROM unioned 
ORDER BY occurred_at DESC