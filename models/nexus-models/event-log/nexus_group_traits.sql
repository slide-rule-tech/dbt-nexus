{{ config(materialized='table', tags=['identity-resolution', 'event-processing', 'groups']) }}
{{ process_entity_traits('group') }} 