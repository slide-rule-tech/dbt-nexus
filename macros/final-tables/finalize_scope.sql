{#
  finalize_scope — wraps a scope model's body to produce the canonical
  nexus_scope_* contract columns.

  Usage:

      with raw_scope_tuples as (
        select
          viewer_entity_id,
          viewer_entity_type,
          resource_entity_id,
          resource_entity_type,
          relationship,
          role,
          source_record_ids,
          granted_at,
          revoked_at
        from ...
      )

      {{ nexus.finalize_scope('advisor_to_household') }}

  The CTE must produce exactly the columns above. finalize_scope adds
  scope_id, scope_name, is_active, _created_at, _updated_at, _processed_at.

  `source_record_ids` is a STRING (semicolon-delimited list of provenance
  IDs — relationship_ids, trait_ids, etc.) rather than an ARRAY so the
  contract is portable across BigQuery and Snowflake. Use `concat(a, ';',
  b)` to join multiple IDs; pass an empty string or NULL when there is
  no provenance to record.

  source_cte defaults to 'raw_scope_tuples' but can be overridden.
#}

{% macro finalize_scope(scope_name, source_cte='raw_scope_tuples') %}

select
    {{ nexus.create_nexus_id('scope', ['viewer_entity_id', 'resource_entity_id', "'" ~ scope_name ~ "'", 'relationship']) }} as scope_id,
    '{{ scope_name }}' as scope_name,
    viewer_entity_id,
    viewer_entity_type,
    resource_entity_id,
    resource_entity_type,
    relationship,
    role,
    source_record_ids,
    granted_at,
    revoked_at,
    (revoked_at is null) as is_active,
    granted_at as _created_at,
    coalesce(revoked_at, granted_at) as _updated_at,
    current_timestamp() as _processed_at
from {{ source_cte }}

{% endmacro %}
