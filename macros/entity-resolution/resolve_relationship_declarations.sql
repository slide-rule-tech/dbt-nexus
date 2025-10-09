{% macro resolve_relationship_declarations() %}

with relationship_declarations as (
    select * from {{ ref('nexus_relationship_declarations') }}
),

-- Get all resolved entity identifiers across all entity types
all_resolved_identifiers as (
    {% set entity_types = var('nexus_entity_types', ['person', 'group']) %}
    {% for entity_type in entity_types %}
    select
        identifier_type,
        identifier_value,
        {{ entity_type }}_id as entity_id,
        '{{ entity_type }}' as entity_type
    from {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }}
    {% if not loop.last %}
    union all
    {% endif %}
    {% endfor %}
),

-- Resolve entity_a identifiers
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

-- Resolve entity_b identifiers
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

