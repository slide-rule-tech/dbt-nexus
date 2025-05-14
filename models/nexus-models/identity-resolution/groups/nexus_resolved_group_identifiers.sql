{{ config(
    materialized='table', 
    tags=['identity-resolution', 'groups'],
) }}

{{ resolve_identifiers('group', 'nexus_group_identifiers', 'nexus_group_identifiers_edges') }}


