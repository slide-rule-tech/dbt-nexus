{{ config(materialized='table', tags=['identity-resolution', 'groups']) }}

{{ resolve_traits('group') }} 