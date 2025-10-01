{{ config(materialized='table', tags=['identity-resolution', 'persons']) }}

{{ nexus.create_identifier_edges('nexus_person_identifiers') }} 