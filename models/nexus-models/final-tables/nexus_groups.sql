{{ config(materialized='table', tags=['identity-resolution', 'groups']) }}

{{ finalize_entity('group') }}