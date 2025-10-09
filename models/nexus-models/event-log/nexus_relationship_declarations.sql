{{ config(materialized='table', tags=['identity-resolution', 'event-processing', 'relationships']) }}

{{ nexus.process_relationship_declarations() }}

