{{ config(
    materialized='table',
    cluster_by=nexus.nexus_cluster_by(['entity_type']),
    post_hook=nexus.nexus_bq_informational_constraints(
        primary_key='entity_id',
        external_foreign_keys=[
            {'on_table': 'nexus_entity_participants',
             'column': 'entity_id',
             'ref_column': 'entity_id'},
        ],
    ),
    tags=['identity-resolution', 'entities']
) }}

{# The external_foreign_keys entry above attaches the
   `nexus_entity_participants.entity_id → nexus_entities.entity_id`
   FK from THIS model's post_hook, not participants'. Reason:
   nexus_entities transitively depends on nexus_entity_participants
   via identity resolution, so a `depends_on` from participants to
   entities would cycle the build graph. By the time this post_hook
   runs, participants already exists. #}

-- depends_on: {{ ref('nexus_computed_traits') }}

{{ nexus.finalize_entities() }}

