{{ config(materialized='table', tags=['identity-resolution', 'event-processing', 'persons']) }}

{{ nexus.process_entity_identifiers('person') }}