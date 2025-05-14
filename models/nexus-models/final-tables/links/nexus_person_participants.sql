{{ config(materialized='table', tags=['identity-resolution', 'persons', 'realtime']) }}

{{ finalize_participants('person') }} 