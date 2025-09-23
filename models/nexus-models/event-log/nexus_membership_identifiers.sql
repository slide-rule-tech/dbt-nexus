{{ config(materialized='table', tags=['identity-resolution', 'event-processing', 'memberships']) }}

{% set relations_to_union = [] %}
{% for source in var('sources') %}
    {% if source.memberships %}
        {% do relations_to_union.append(ref(source.name ~ '_membership_identifiers')) %}
    {% endif %}
{% endfor %}

{% if relations_to_union %}
with unioned as (
    {{ dbt_utils.union_relations(
        relations=relations_to_union
    ) }}
)

select
   *
from unioned 
{% else %}
-- Return empty result when no membership sources are configured
with empty_result as (
    select
        cast(null as string) as identifier_id,
        cast(null as string) as event_id,
        cast(null as timestamp) as occurred_at,
        cast(null as string) as person_identifier,
        cast(null as string) as person_identifier_type,
        cast(null as string) as group_identifier,
        cast(null as string) as group_identifier_type,
        cast(null as string) as role,
        cast(null as string) as source
    where 1 = 0
)

select * from empty_result
{% endif %} 