{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('bodies', false),
    materialized='view',
    tags=['gmail', 'base', 'bodies']
) }}

-- Base layer: raw collection, zero transformation overhead. Bodies land here
-- from either the gmail_message_body BBP enricher (lean BBP envelope) or the
-- Workspace Gmail ingestion's gmailBodies option (standard ingestion
-- envelope); the body fields live in _raw_record either way. JSON extraction
-- + casting happen in the normalized layer.
select * from {{ source('gmail', 'message_bodies') }}
