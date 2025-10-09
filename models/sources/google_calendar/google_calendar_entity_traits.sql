{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'entity_traits', 'google_calendar']
) }}

-- Union all entity traits using dbt_utils for column handling
{{ dbt_utils.union_relations(
    relations=[
        ref('google_calendar_person_traits'),
        ref('google_calendar_group_traits')
    ]
) }}

order by occurred_at desc

