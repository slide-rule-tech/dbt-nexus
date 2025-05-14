{{ config(materialized='table', tags=['identity-resolution', 'persons']) }}

{{ finalize_entity('person') }}