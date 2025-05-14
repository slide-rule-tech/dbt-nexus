{{ config(materialized='table', tags=['identity-resolution', 'persons']) }}

{{ nexus_create_identifier_edges('person_identifiers') }} 