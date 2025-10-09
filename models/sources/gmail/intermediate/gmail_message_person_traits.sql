{{ config(
    enabled=var('nexus', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'person_traits']
) }}

-- Extract person traits from gmail messages
with gmail_messages as (
    select * from {{ ref('gmail_messages') }}
),

sender_traits as (
    -- Sender name trait
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'sender.email', "'person'", "'name'", "'sender'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        sender.email as identifier_value,
        'name' as trait_name,
        sender.name as trait_value,
        'gmail' as source,
        occurred_at,
        synced_at as _ingested_at
    from gmail_messages
    where sender.name is not null

    union all

    -- Sender email trait
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'sender.email', "'person'", "'email'", "'sender'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        sender.email as identifier_value,
        'email' as trait_name,
        sender.email as trait_value,
        'gmail' as source,
        occurred_at,
        synced_at as _ingested_at
    from gmail_messages
    where sender.email is not null
),

recipient_traits as (
    -- Recipient name trait
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'recipient.email', "'person'", "'name'", "'recipient'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        recipient.email as identifier_value,
        'name' as trait_name,
        recipient.name as trait_value,
        'gmail' as source,
        occurred_at,
        synced_at as _ingested_at
    from gmail_messages,
    unnest(recipients) as recipient
    where recipient.name is not null

    union all

    -- Recipient email trait
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'recipient.email', "'person'", "'email'", "'recipient'"]) }} as entity_trait_id,
        event_id,
        'person' as entity_type,
        'email' as identifier_type,
        recipient.email as identifier_value,
        'email' as trait_name,
        recipient.email as trait_value,
        'gmail' as source,
        occurred_at,
        synced_at as _ingested_at
    from gmail_messages,
    unnest(recipients) as recipient
    where recipient.email is not null
)

select * from sender_traits
union all
select * from recipient_traits
order by occurred_at desc

