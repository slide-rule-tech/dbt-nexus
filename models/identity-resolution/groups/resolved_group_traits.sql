{{ config(materialized='table', tags=['identity-resolution', 'groups']) }}

{{ nexus_resolve_traits('group') }} 