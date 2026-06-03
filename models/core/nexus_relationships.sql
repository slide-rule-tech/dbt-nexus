{{ config(
    materialized='table',
    cluster_by=nexus.nexus_cluster_by(['relationship_type', 'entity_a_type', 'entity_b_type']),
    post_hook=nexus.nexus_bq_informational_constraints(
        primary_key='relationship_id',
        foreign_keys=[
            {'column': 'entity_a_id', 'ref_table': 'nexus_entities', 'ref_column': 'entity_id'},
            {'column': 'entity_b_id', 'ref_table': 'nexus_entities', 'ref_column': 'entity_id'},
        ],
    ),
    tags=['identity-resolution', 'relationships']
) }}

-- depends_on: {{ ref('nexus_entities') }}
-- ^ ensures nexus_entities finishes (PK constraint added by its post_hook)
--   before this model's FKs to nexus_entities.entity_id are added.

{{ nexus.finalize_relationships() }}

