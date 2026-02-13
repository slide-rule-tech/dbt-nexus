{{ config(materialized='table', tags=['identity-resolution', 'entities']) }}

{{ nexus.finalize_entities() }}

