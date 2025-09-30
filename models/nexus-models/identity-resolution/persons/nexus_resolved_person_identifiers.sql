{{ config(
    materialized='table', 
    tags=['identity-resolution', 'persons'],
) }}

{{ nexus.resolve_identifiers('person', 'nexus_person_identifiers', 'nexus_person_identifiers_edges', var('nexus_max_recursion')) }}