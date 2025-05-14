{{ config(materialized='table', tags=['identity-resolution', 'event-processing', 'persons']) }}

{{ process_entity_identifiers('person') }}