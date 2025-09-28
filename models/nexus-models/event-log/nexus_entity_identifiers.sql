{{ config(materialized='table', tags=['identity-resolution', 'event-processing']) }}

{{ process_entity_identifiers() }}