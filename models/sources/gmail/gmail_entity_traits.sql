{{ config(
    enabled=var('nexus', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'entity_traits', 'gmail']
) }}

-- Union all person and group traits using dbt_utils for column handling
{{ dbt_utils.union_relations(
    relations=[
        ref('gmail_message_person_traits'),
        ref('gmail_message_group_traits')
    ]
) }}

order by occurred_at desc

