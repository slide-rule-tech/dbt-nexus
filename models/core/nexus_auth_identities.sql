{{ config(materialized='view', tags=['permissions', 'identities']) }}

{#
  nexus_auth_identities — default impl.

  Maps an authenticated session subject (typically an email) to a person
  entity_id by lowercase-email match on nexus_entities.

  Clients that need alias support, manual overrides, or service-account
  mappings should create a project-level model with the same name to
  override this default.
#}

with people as (
    select
        entity_id,
        lower(email) as email_normalized,
        coalesce(_created_at, current_timestamp()) as established_at
    from {{ ref('nexus_entities') }}
    where entity_type = 'person'
      and email is not null
      and trim(email) != ''
)

select
    {{ nexus.create_nexus_id('auth_identity', ["'email'", 'email_normalized', 'entity_id']) }} as auth_identity_id,
    'email' as auth_provider,
    email_normalized as auth_subject,
    entity_id,
    'email_exact' as match_method,
    true as is_active,
    established_at
from people
