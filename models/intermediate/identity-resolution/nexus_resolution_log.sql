{{ config(
    enabled=nexus.nexus_incremental_enabled(),
    materialized='incremental',
    full_refresh=false,
    tags=['identity-resolution'],
) }}

{# Append-only record of every identity-resolution decision: entities born,
   identifiers accreted, and merges (rows re-pointed from a losing entity to
   a survivor). This is the change-set downstream consumers key off -- the
   set of entity_ids affected by a run is exactly the entity_ids appearing
   here, and 'repointed' rows double as an outbound merge/alias protocol for
   external tools.

   Unlike every other model in the package, this table is NOT derivable from
   source data: it records the history of what the pipeline concluded and
   when, which is path-dependent on ingestion order. full_refresh=false
   protects it; a full refresh of the resolver appends a new
   'full_resolution' epoch here rather than erasing history. #}

{% set er_types = nexus.get_er_entity_types() %}

with changes as (
    {% for entity_type in er_types %}
    select
        '{{ entity_type }}' as entity_type,
        identifier_type,
        identifier_value,
        {{ entity_type }}_id as entity_id,
        previous_entity_id,
        resolution_reason,
        resolved_at_watermark
    from {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }}
    {% if not loop.last %}
    union all
    {% endif %}
    {% endfor %}
)

select
    {{ nexus.create_nexus_id('resolution', ['entity_type', 'identifier_type', 'identifier_value', 'entity_id', 'resolution_reason', 'resolved_at_watermark']) }} as resolution_id,
    entity_type,
    identifier_type,
    identifier_value,
    entity_id,
    previous_entity_id,
    resolution_reason,
    resolved_at_watermark
from changes
{% if is_incremental() %}
where resolved_at_watermark > coalesce(
    (select max(resolved_at_watermark) from {{ this }}),
    cast('1970-01-01' as timestamp)
)
{% endif %}
