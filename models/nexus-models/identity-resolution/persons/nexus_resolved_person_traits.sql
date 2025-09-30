{{ config(materialized='table', tags=['identity-resolution', 'persons']) }}

{{ nexus.resolve_traits('person') }}