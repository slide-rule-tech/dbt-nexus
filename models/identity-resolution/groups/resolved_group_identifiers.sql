{{ config(
    materialized='table', 
    tags=['identity-resolution', 'groups'],
) }}

{{ nexus_resolve_identifiers('group', 'group_identifiers', 'group_identifiers_edges') }}


