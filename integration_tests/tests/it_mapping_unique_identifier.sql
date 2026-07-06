{{ config(tags=["it_invariant"]) }}

-- The mapping is a function: exactly one row (one entity) per identifier.
{% for t in ['person', 'group'] %}
select
    '{{ t }}' as entity_type,
    identifier_type,
    identifier_value,
    count(*) as n_rows
from {{ ref('nexus_resolved_' ~ t ~ '_identifiers') }}
group by 1, 2, 3
having count(*) > 1
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
