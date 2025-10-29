{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='view',
    tags=['gmail', 'base']
) }}

-- Base layer: Raw table with zero transformation overhead
select * from {{ source('gmail', 'messages') }}
