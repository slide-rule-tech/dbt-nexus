{{ config(materialized='table', tags=['identity-resolution', 'groups']) }}

{{ create_identifier_edges('nexus_group_identifiers') }} 