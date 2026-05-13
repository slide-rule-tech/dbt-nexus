{{ config(materialized='view', tags=['permissions', 'scopes']) }}

{#
  nexus_scopes — union view across the project's nexus_scope_* models.
  Single read surface for the permission translation layer.

  Clients opt in by declaring their scope models in dbt_project.yml:

      vars:
        nexus_scope_models:
          - nexus_scope_advisor_to_household
          - nexus_scope_advisor_to_account
          - nexus_scope_admin_view_all_accounts

  Projects that don't set the var get an empty stub matching the contract
  columns — they still build, just with zero rows.
#}

{% set scope_models = var('nexus_scope_models', []) %}

{% if scope_models | length == 0 %}

select
    cast(null as {{ dbt.type_string() }}) as scope_id,
    cast(null as {{ dbt.type_string() }}) as scope_name,
    cast(null as {{ dbt.type_string() }}) as viewer_entity_id,
    cast(null as {{ dbt.type_string() }}) as viewer_entity_type,
    cast(null as {{ dbt.type_string() }}) as resource_entity_id,
    cast(null as {{ dbt.type_string() }}) as resource_entity_type,
    cast(null as {{ dbt.type_string() }}) as relationship,
    cast(null as {{ dbt.type_string() }}) as role,
    cast(null as array<{{ dbt.type_string() }}>) as source_record_ids,
    cast(null as timestamp) as granted_at,
    cast(null as timestamp) as revoked_at,
    cast(false as boolean) as is_active,
    cast(null as timestamp) as _created_at,
    cast(null as timestamp) as _updated_at,
    cast(null as timestamp) as _processed_at
where 1 = 0

{% else %}

{% for model_name in scope_models %}
select
    scope_id,
    scope_name,
    viewer_entity_id,
    viewer_entity_type,
    resource_entity_id,
    resource_entity_type,
    relationship,
    role,
    source_record_ids,
    granted_at,
    revoked_at,
    is_active,
    _created_at,
    _updated_at,
    _processed_at
from {{ ref(model_name) }}
{% if not loop.last %}
union all
{% endif %}
{% endfor %}

{% endif %}
