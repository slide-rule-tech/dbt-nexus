{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'entity_identifiers', 'google_calendar']
) }}

-- Union all entity identifiers using dbt_utils for column handling
{{ dbt_utils.union_relations(
    relations=[
        ref('google_calendar_person_identifiers'),
        ref('google_calendar_group_identifiers')
    ]
) }}

order by occurred_at desc

