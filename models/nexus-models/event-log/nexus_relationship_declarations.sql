{{ config(materialized='table', tags=['identity-resolution', 'event-processing', 'relationships']) }}

{% set relations_to_union = [] %}
{% set nexus_config = var('nexus', {}) %}
{% set sources_config = nexus_config.get('sources', {}) %}

{% for source_name, source_config in sources_config.items() %}
    {% if source_config.get('enabled') and source_config.get('relationships') %}
        {% do relations_to_union.append(ref(source_name ~ '_relationship_declarations')) %}
    {% endif %}
{% endfor %}

{% if relations_to_union %}
    {{ nexus.process_relationship_declarations() }}
{% else %}
WITH empty_result AS (
    SELECT 
        CAST(NULL AS STRING) as relationship_declaration_id,
        CAST(NULL AS STRING) as event_id,
        CAST(NULL AS TIMESTAMP) as occurred_at,
        CAST(NULL AS STRING) as entity_a_identifier,
        CAST(NULL AS STRING) as entity_a_identifier_type,
        CAST(NULL AS STRING) as entity_a_type,
        CAST(NULL AS STRING) as entity_a_role,
        CAST(NULL AS STRING) as entity_b_identifier,
        CAST(NULL AS STRING) as entity_b_identifier_type,
        CAST(NULL AS STRING) as entity_b_type,
        CAST(NULL AS STRING) as entity_b_role,
        CAST(NULL AS STRING) as relationship_type,
        CAST(NULL AS STRING) as relationship_direction,
        {% if target.type == 'snowflake' %}
        CAST(NULL AS BOOLEAN) as is_active,
        {% else %}
        CAST(NULL AS BOOL) as is_active,
        {% endif %}
        CAST(NULL AS STRING) as source
)
SELECT 
    relationship_declaration_id,
    event_id,
    occurred_at,
    entity_a_identifier,
    entity_a_identifier_type,
    entity_a_type,
    entity_a_role,
    entity_b_identifier,
    entity_b_identifier_type,
    entity_b_type,
    entity_b_role,
    relationship_type,
    relationship_direction,
    is_active,
    source
FROM empty_result
WHERE 1 = 0
{% endif %}

