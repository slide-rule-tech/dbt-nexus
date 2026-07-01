{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('bodies', false),
    materialized='view',
    tags=['gmail', 'base', 'bodies']
) }}

-- Base layer: raw collection, zero transformation overhead. The gmail_message_body
-- BBP enricher lands bodies here (lean BBP envelope; body fields in _raw_record).
-- JSON extraction + casting happen in the normalized layer.
select * from {{ source('gmail', 'message_bodies') }}
