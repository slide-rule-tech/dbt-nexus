{{ config(materialized='table', tags=['identity-resolution', 'groups']) }}

{{ nexus_finalize_entity('group') }}