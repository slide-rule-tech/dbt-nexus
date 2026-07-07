{{ config(materialized='view', tags=['permissions', 'identities']) }}

{#
  nexus_auth_identities — default impl.

  Maps an authenticated session subject (typically an email) to a person
  entity_id by lowercase-email match on nexus_entities.

  The default requires an `email` column on nexus_entities, which only
  exists when the project configures an `email` trait on person entities.
  Projects without that trait get an empty stub matching the contract
  columns — they still build, just with zero rows (no email-based auth
  identities). Add the email trait, or override this model at the project
  level, to populate it.

  Clients that need alias support, manual overrides, or service-account
  mappings should create a project-level model with the same name to
  override this default.
#}

{% set entity_columns = [] %}
{% if execute %}
    {% set entity_columns = adapter.get_columns_in_relation(ref('nexus_entities'))
        | map(attribute='name') | map('lower') | list %}
{% endif %}

{% if 'email' in entity_columns %}

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

{% else %}

-- nexus_entities has no `email` column for this project's trait config →
-- no email-based auth identities. Empty stub with the full contract column
-- shape. The `where 1 = 0` filter needs a FROM in BigQuery and Snowflake, so
-- we select from a one-row dummy and immediately filter it out.
select
    cast(null as {{ dbt.type_string() }}) as auth_identity_id,
    cast(null as {{ dbt.type_string() }}) as auth_provider,
    cast(null as {{ dbt.type_string() }}) as auth_subject,
    cast(null as {{ dbt.type_string() }}) as entity_id,
    cast(null as {{ dbt.type_string() }}) as match_method,
    cast(false as boolean) as is_active,
    cast(null as timestamp) as established_at
from (select 1) _empty_auth_identities_stub
where 1 = 0

{% endif %}
