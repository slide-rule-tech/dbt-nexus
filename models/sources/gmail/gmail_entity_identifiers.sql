{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'entity_identifiers', 'gmail']
) }}

-- Union all person and group identifiers using dbt_utils for column handling
{{ dbt_utils.union_relations(
    relations=[
        ref('gmail_message_person_identifiers'),
        ref('gmail_message_group_identifiers')
    ]
) }}

order by occurred_at desc

