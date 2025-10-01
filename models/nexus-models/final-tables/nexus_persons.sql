{{ config(materialized='table', tags=['identity-resolution', 'persons']) }}

{{ nexus.finalize_entity('person') }}