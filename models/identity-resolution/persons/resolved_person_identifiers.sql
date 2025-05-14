{{ config(
    materialized='table', 
    tags=['identity-resolution', 'persons'],
) }}


{{ nexus_resolve_identifiers('person', 'person_identifiers', 'person_identifiers_edges') }}