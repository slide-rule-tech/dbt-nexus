{% macro register_entities(source_model, entity_type, source, source_id_column, trait_columns=[], created_at_column=none, updated_at_column=none) %}
{# Lightweight entity registration for non-ER entity types.
   Generates a deterministic entity_id from the source record ID
   without going through entity resolution.

   Usage:
     {{ nexus.register_entities(
         source_model='stripe_subscriptions_combined',
         entity_type='subscription',
         source='stripe',
         source_id_column='id',
         trait_columns=['currency', 'billing_interval', 'plan_name'],
         created_at_column='created_at',
         updated_at_column='_updated_at'
     ) }}

   Args:
     source_model: Name of the ref() model containing source records
     entity_type: Entity type string (e.g., 'subscription', 'contract')
     source: Source system name (e.g., 'stripe', 'upwork')
     source_id_column: Column on the source model that uniquely identifies each record
     trait_columns: List of column names to carry through as entity traits/attributes
     created_at_column: Optional source column with the entity's creation timestamp
     updated_at_column: Optional source column with the entity's last-updated timestamp
#}

SELECT
    {{ nexus.create_nexus_id('entity', [source_id_column, "'" ~ source ~ "'"]) }} as entity_id,
    '{{ entity_type }}' as entity_type,
    '{{ source }}' as source,
    CAST({{ source_id_column }} AS STRING) as source_id,
    {% for col in trait_columns %}
    {{ col }},
    {% endfor %}
    {% if created_at_column %}
    CAST({{ created_at_column }} AS TIMESTAMP) as _source_created_at,
    {% else %}
    CAST(NULL AS TIMESTAMP) as _source_created_at,
    {% endif %}
    {% if updated_at_column %}
    CAST({{ updated_at_column }} AS TIMESTAMP) as _source_updated_at,
    {% else %}
    CAST(NULL AS TIMESTAMP) as _source_updated_at,
    {% endif %}
    CURRENT_TIMESTAMP() as _registered_at
FROM {{ ref(source_model) }}
WHERE {{ source_id_column }} IS NOT NULL

{% endmacro %}
