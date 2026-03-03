
{% set er_types = nexus.get_er_entity_types() %}
{% set non_er_types = nexus.get_non_er_entity_types() %}
{% set entity_config = nexus.get_entity_type_config() %}

{% for entity_type in er_types %}
    select
        {{ entity_type }}_id as identifier_id,
        identifier_type,
        identifier_value,
        {{ entity_type }}_id as entity_id,
        '{{ entity_type }}' as entity_type
    from {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }}
    {% if not loop.last or non_er_types | length > 0 %}
    union all
    {% endif %}
{% endfor %}

{% for entity_type in non_er_types %}
    {% set type_config = entity_config[entity_type] %}
    {% set reg_model = type_config.get('registration_model') %}
    {% if reg_model %}
    select
        entity_id as identifier_id,
        '{{ entity_type }}_id' as identifier_type,
        source_id as identifier_value,
        entity_id,
        '{{ entity_type }}' as entity_type
    from {{ ref(reg_model) }}

    union all

    select distinct
        reg.entity_id as identifier_id,
        nei.identifier_type,
        nei.identifier_value,
        reg.entity_id as entity_id,
        '{{ entity_type }}' as entity_type
    from {{ ref('nexus_entity_identifiers') }} nei
    inner join {{ ref(reg_model) }} reg
        on nei.entity_type = '{{ entity_type }}'
       and nei.identifier_value = reg.source_id
    where nei.entity_type = '{{ entity_type }}'

    {% if not loop.last %}
    union all
    {% endif %}
    {% endif %}
{% endfor %}
