{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'relationship_declarations', 'google_calendar']
) }}

-- Union all relationship declarations using dbt_utils for column handling
-- Future: add google_calendar_label_relationships if needed
{{ dbt_utils.union_relations(
    relations=[
        ref('google_calendar_event_relationship_declarations')
    ]
) }}

order by occurred_at desc

