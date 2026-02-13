{{ config(materialized='table', tags=['identity-resolution', 'entities']) }}

{{ nexus.create_identifier_edges('nexus_entity_identifiers') }}

