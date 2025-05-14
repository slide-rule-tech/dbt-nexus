{{ config(materialized='table', tags=['identity-resolution', 'persons', 'realtime']) }}

{{ nexus_finalize_participants('person') }} 