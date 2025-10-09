{{ config(materialized='table', tags=['identity-resolution', 'relationships']) }}

{{ nexus.finalize_relationships() }}

