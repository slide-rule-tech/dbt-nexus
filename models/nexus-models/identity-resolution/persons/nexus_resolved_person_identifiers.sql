{{ config(
    materialized='table', 
    tags=['identity-resolution', 'persons'],
) }}


{{ resolve_identifiers('person', 'nexus_person_identifiers', 'nexus_person_identifiers_edges') }}