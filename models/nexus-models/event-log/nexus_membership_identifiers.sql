{{ config(materialized='table', tags=['identity-resolution', 'event-processing', 'memberships']) }}

{% set relations_to_union = [] %}
{% for source in var('sources') %}
    {% if source.memberships %}
        {% do relations_to_union.append(ref(source.name ~ '_membership_identifiers')) %}
    {% endif %}
{% endfor %}

with unioned as (
    {{ dbt_utils.union_relations(
        relations=relations_to_union
    ) }}
)

select
   *
from unioned 