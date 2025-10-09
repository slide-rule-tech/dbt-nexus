{{ config(
    enabled=var('nexus', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'relationship_declarations', 'gmail']
) }}

-- Union all relationship declarations using dbt_utils for column handling
-- Future: add gmail_label_relationships, gmail_thread_relationships
{{ dbt_utils.union_relations(
    relations=[
        ref('gmail_message_relationship_declarations')
    ]
) }}

order by occurred_at desc

