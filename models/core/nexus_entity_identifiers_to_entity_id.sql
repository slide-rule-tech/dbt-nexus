
{% set entity_types = var('nexus', {}).get('entity_types') %}
{% for entity_type in entity_types %}
    select
        {{ entity_type }}_id as identifier_id,
        identifier_type,
        identifier_value,
        {{ entity_type }}_id as entity_id,
        '{{ entity_type }}' as entity_type
    from {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }}
    {% if not loop.last %}
    union all
    {% endif %}
{% endfor %}