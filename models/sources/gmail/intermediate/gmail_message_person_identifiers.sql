{{ config(
    enabled=var('nexus', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'person_identifiers']
) }}

-- Extract person identifiers from gmail messages
with gmail_messages as (
    select * from {{ ref('gmail_messages') }}
),

sender_identifiers as (
    select 
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'sender.email', "'person'", "'sender'"]) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'person' as entity_type,
        'email' as identifier_type,
        sender.email as identifier_value,
        'gmail' as source,
        occurred_at,
        synced_at as _ingested_at,
        'sender' as role
    from gmail_messages
    where sender.email is not null
),

recipient_identifiers as (
    select 
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'recipient.email', "'person'", "'recipient'"]) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'person' as entity_type,
        'email' as identifier_type,
        recipient.email as identifier_value,
        'gmail' as source,
        occurred_at,
        synced_at as _ingested_at,
        'recipient' as role
    from gmail_messages,
    unnest(recipients) as recipient
    where recipient.email is not null
)

select * from sender_identifiers
union all
select * from recipient_identifiers
order by occurred_at desc

