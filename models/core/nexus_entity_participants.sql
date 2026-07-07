{{ config(
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('occurred_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['entity_type', 'event_id']),
    unique_key='entity_participant_id',
    on_schema_change='append_new_columns',
    post_hook=nexus.nexus_bq_informational_constraints(
        primary_key='entity_participant_id',
        foreign_keys=[
            {'column': 'event_id', 'ref_table': 'nexus_events', 'ref_column': 'event_id'},
        ],
    ),
    tags=['identity-resolution', 'participants', 'realtime']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', '_resolution_log_watermark']) }}

{# Monthly (not daily) partitioning on occurred_at: participant data
   inherits timestamps from every event source the package unions in
   (Gmail history, calendar history, etc.) and routinely spans more
   than the 4000-partition BigQuery cap when partitioned daily.
   Monthly granularity gives 4000 / 12 ≈ 333 years of headroom and
   still gives downstream queries a ~4-partition prune on a 90-day
   window.

   The FK on entity_id → nexus_entities is intentionally NOT declared
   here; it's attached by nexus_entities' post_hook (as an
   external_foreign_keys entry), because nexus_entities transitively
   depends on this model via identity resolution and a `depends_on`
   from here to entities would cycle the build graph. #}

-- depends_on: {{ ref('nexus_events') }}
-- ^ ensures nexus_events finishes (PK constraint added by its post_hook)
--   before this model's FK to nexus_events.event_id is added.

{% set er_types = nexus.get_er_entity_types() %}
{% set non_er_types = nexus.get_non_er_entity_types() %}
{% set entity_config = nexus.get_entity_type_config() %}

{% if nexus.nexus_incremental_enabled() %}
{# Incremental mode: append legs (new-event rows, watermark on the
   entity-identifiers clock) plus, on incremental runs, a repoint leg per ER
   type driven by nexus_resolution_log 'repointed' rows past this table's
   own _resolution_log_watermark cursor. entity_participant_id is stable at
   birth — merges update entity_id in place. See
   incremental_finalize_participants.sql for the leg SQL and the accepted
   post-merge duplicate-grain divergence. #}

-- depends_on: {{ ref('nexus_resolution_log') }}
{# ^ the repoint CTEs live inside is_incremental() and the log ref would be
   invisible to parse-time extraction; the log must build first (it also
   supplies the cursor stamp below). #}

with
{% for entity_type in er_types %}
{{ entity_type }}_participants as (
  {{ nexus.incremental_finalize_participants(entity_type) }}
),
{% endfor %}
{% for entity_type in non_er_types %}
{{ entity_type }}_participants as (
  {{ nexus.incremental_finalize_non_er_participants(entity_type) }}
),
{% endfor %}
{% if is_incremental() %}
{% for entity_type in er_types %}
{{ entity_type }}_repointed as (
  {{ nexus.incremental_participants_repoint(entity_type) }}
),
{% endfor %}
{% endif %}

unioned as (
{% set all_types = er_types + non_er_types %}
{% for entity_type in all_types %}
  select * from {{ entity_type }}_participants
  {{ "union all" if not loop.last }}
{% endfor %}
{% if is_incremental() %}
{% for entity_type in er_types %}
  union all
  select * from {{ entity_type }}_repointed
{% endfor %}
{% endif %}
)

select
  entity_participant_id,
  entity_type,
  event_id,
  entity_id,
  role,
  occurred_at,
  _ingested_at,
  {# Cursor bookkeeping: every emitted row is stamped with the CURRENT log
     head; the next run's repoint window is (max(stored), new head]. A
     zero-row run leaves the cursor put — replaying a window is a no-op
     because replayed rows no longer sit at previous_entity_id. The
     load_relation guard covers `dbt compile` against a database where the
     log doesn't exist yet; at run time depends_on guarantees it does. #}
  {%- if execute and load_relation(ref('nexus_resolution_log')) is not none %}
  {{ nexus.nexus_incremental_watermark_literal('resolved_at_watermark', relation=ref('nexus_resolution_log')) }} as _resolution_log_watermark
  {%- else %}
  cast('1970-01-01' as timestamp) as _resolution_log_watermark
  {%- endif %}
from unioned
{% if is_incremental() %}
{# Append and repoint can emit the same id in one batch (they agree on the
   destination entity) — keep one deterministically. #}
qualify row_number() over (partition by entity_participant_id order by entity_id) = 1
{% endif %}

{% else %}
{# Full-resolution mode (flag off): unchanged original path. #}

with
{% for entity_type in er_types %}
{{ entity_type }}_participants as (
  {{ nexus.finalize_participants(entity_type) }}
){{ "," if not loop.last or non_er_types | length > 0 }}
{% endfor %}

{% for entity_type in non_er_types %}
{{ entity_type }}_participants as (
  {{ nexus.finalize_non_er_participants(entity_type) }}
){{ "," if not loop.last }}
{% endfor %}

{% set all_types = er_types + non_er_types %}
{% for entity_type in all_types %}
{% if loop.first %}
select * from {{ entity_type }}_participants
{% else %}
union all
select * from {{ entity_type }}_participants
{% endif %}
{% endfor %}

{% endif %}
