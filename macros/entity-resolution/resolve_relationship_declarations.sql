{% macro resolve_relationship_declarations() %}

{% set er_types = nexus.get_er_entity_types() %}
{% set non_er_types = nexus.get_non_er_entity_types() %}
{% set entity_config = nexus.get_entity_type_config() %}

with relationship_declarations as (
    select * from {{ ref('nexus_relationship_declarations') }}
),

all_resolved_identifiers as (
    {% for entity_type in er_types %}
    select
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
        '{{ entity_type }}_id' as identifier_type,
        source_id as identifier_value,
        entity_id,
        '{{ entity_type }}' as entity_type
    from {{ ref(reg_model) }}

    union all

    -- Also map source-specific non-ER identifier types (e.g. orion_account_id)
    -- when they point to the same registered source_id.
    select distinct
        nei.identifier_type,
        nei.identifier_value,
        reg.entity_id,
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
),

relationships_with_entity_a as (
    select
        rd.relationship_declaration_id,
        rd.event_id,
        rd.occurred_at,
        ea.entity_id as entity_a_id,
        rd.entity_a_type,
        rd.entity_a_role,
        rd.entity_b_identifier,
        rd.entity_b_identifier_type,
        rd.entity_b_type,
        rd.entity_b_role,
        rd.relationship_type,
        rd.relationship_direction,
        rd.is_active,
        rd.source
    from relationship_declarations rd
    left join all_resolved_identifiers ea
        on rd.entity_a_identifier = ea.identifier_value
        and rd.entity_a_identifier_type = ea.identifier_type
        and rd.entity_a_type = ea.entity_type
),

relationships_with_both_entities as (
    select
        r.relationship_declaration_id,
        r.event_id,
        r.occurred_at,
        r.entity_a_id,
        r.entity_a_type,
        r.entity_a_role,
        eb.entity_id as entity_b_id,
        r.entity_b_type,
        r.entity_b_role,
        r.relationship_type,
        r.relationship_direction,
        r.is_active,
        r.source
    from relationships_with_entity_a r
    left join all_resolved_identifiers eb
        on r.entity_b_identifier = eb.identifier_value
        and r.entity_b_identifier_type = eb.identifier_type
        and r.entity_b_type = eb.entity_type
)

select
    relationship_declaration_id,
    event_id,
    occurred_at,
    entity_a_id,
    entity_a_type,
    entity_a_role,
    entity_b_id,
    entity_b_type,
    entity_b_role,
    relationship_type,
    relationship_direction,
    is_active,
    source
from relationships_with_both_entities
where entity_a_id is not null
    and entity_b_id is not null

{% endmacro %}
