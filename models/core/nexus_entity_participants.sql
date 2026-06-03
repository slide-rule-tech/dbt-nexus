{{ config(
    materialized='table',
    partition_by=nexus.nexus_bq_partition_by('occurred_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['entity_type', 'event_id']),
    post_hook=nexus.nexus_bq_informational_constraints(
        primary_key='entity_participant_id',
        foreign_keys=[
            {'column': 'event_id', 'ref_table': 'nexus_events', 'ref_column': 'event_id'},
        ],
    ),
    tags=['identity-resolution', 'participants', 'realtime']
) }}

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
