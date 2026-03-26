{{ config(materialized='table', tags=['identity-resolution', 'entities']) }}

-- depends_on: {{ ref('nexus_computed_traits') }}

{{ nexus.finalize_entities() }}

