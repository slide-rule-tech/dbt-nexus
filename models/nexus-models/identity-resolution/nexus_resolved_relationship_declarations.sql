{{ config(materialized='table', tags=['identity-resolution', 'relationships']) }}

{{ nexus.resolve_relationship_declarations() }}

