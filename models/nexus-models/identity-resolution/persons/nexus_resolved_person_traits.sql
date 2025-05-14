{{ config(materialized='table', tags=['identity-resolution', 'persons']) }}

{{ resolve_traits('person') }}