{{ config(materialized = 'table')}}

{# Collect relations to union based on sources with attribution #}
{% set relations_to_union = [] %}
{% for source in var('sources') %}
    {% if source.attribution %}
        {% do relations_to_union.append(ref(source.name ~ '_touchpoints')) %}
    {% endif %}
{% endfor %}

{% if relations_to_union %}
    {{ dbt_utils.union_relations(
        relations=relations_to_union
    ) }}
{% else %}
    {# Return empty result if no relations found #}
    select 
        cast(null as string) as touchpoint_id,
        cast(null as string) as touchpoint_event_id,
        cast(null as timestamp) as occurred_at,
        cast(null as string) as touchpoint_type,
        cast(null as string) as source,
        cast(null as string) as medium,
        cast(null as string) as campaign,
        cast(null as string) as content,
        cast(null as string) as term,
        cast(null as string) as landing_page,
        cast(null as string) as referrer,
        cast(null as string) as landing_url,
        cast(null as string) as fbclid,
        cast(null as string) as gclid,
        cast(null as string) as attribution_deduplication_key
    where 1=0
{% endif %}
