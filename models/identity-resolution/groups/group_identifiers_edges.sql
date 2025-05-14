{{ config(materialized='table', tags=['identity-resolution', 'groups']) }}

{{ nexus_create_identifier_edges('group_identifiers') }} 