{{ config(materialized='table', tags=['identity-resolution', 'event-processing', 'entities']) }}

{{ nexus.process_entity_traits() }}

