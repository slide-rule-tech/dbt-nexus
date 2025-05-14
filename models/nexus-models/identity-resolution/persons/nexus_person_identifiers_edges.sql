{{ config(materialized='table', tags=['identity-resolution', 'persons']) }}

{{ create_identifier_edges('nexus_person_identifiers') }} 