{{ config(materialized='table', tags=['identity-resolution', 'persons']) }}

{{ nexus_resolve_traits('person') }}