{{ config(materialized='table', tags=['identity-resolution', 'persons']) }}

{{ nexus_finalize_entity('person') }}