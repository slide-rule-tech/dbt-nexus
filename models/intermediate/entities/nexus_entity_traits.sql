{{ config(materialized='table', tags=['identity-resolution', 'event-processing', 'entities']) }}

with processed_traits as (
  {{ nexus.process_entity_traits() }}
),

-- Add internal user traits based on email addresses
internal_user_traits as (
  select
    {{ nexus.create_nexus_id('entity_trait', ['ei.entity_identifier_id', "'is_internal_user'", "'true'", 'ei.occurred_at']) }} as entity_trait_id,
    ei.event_id,
    'person' as entity_type,
    'email' as identifier_type,
    ei.identifier_value,
    'is_internal_user' as trait_name,
    'true' as trait_value,
    'system' as source,
    ei.occurred_at
  from {{ ref('nexus_entity_identifiers') }} ei
  where ei.identifier_type = 'email'
    and ei.entity_type = 'person'
    {% set internal_emails = var('nexus', {}).get('internal_emails', []) %}
    {% if internal_emails and internal_emails | length > 0 %}
    and ei.identifier_value in (
      {% for email in internal_emails %}
        '{{ email }}'{% if not loop.last %},{% endif %}
      {% endfor %}
    )
    {% else %}
    -- No internal emails defined, return empty result
    and 1 = 0
    {% endif %}
)

-- Union processed traits with internal user traits
select
  entity_trait_id,
  event_id,
  entity_type,
  identifier_type,
  identifier_value,
  trait_name,
  trait_value,
  source,
  occurred_at
from processed_traits

union all

select
  entity_trait_id,
  event_id,
  entity_type,
  identifier_type,
  identifier_value,
  trait_name,
  trait_value,
  source,
  occurred_at
from internal_user_traits

