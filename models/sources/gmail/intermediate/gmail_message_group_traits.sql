{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'group_traits']
) }}

-- Extract group (domain) traits from gmail messages
with gmail_messages as (
    select * from {{ ref('gmail_messages') }}
),

-- Extract domains from sender emails
sender_domains as (
    select 
        event_id,
        occurred_at,
        synced_at,
        sender.domain as domain
    from gmail_messages
    where sender.domain is not null
      and not sender.generic_domain
),

-- Extract domains from recipient emails
recipient_domains as (
    select 
        event_id,
        occurred_at,
        synced_at,
        recipient.domain as domain
    from gmail_messages,
    unnest(recipients) as recipient
    where recipient.domain is not null
      and not recipient.generic_domain
),

-- Union all domains (use DISTINCT to avoid duplicate domain per event)
all_domains as (
    select * from sender_domains
    union distinct
    select * from recipient_domains
),

-- Create domain traits
domain_traits as (
    -- Domain as a trait (for searchability)
    select
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'domain', "'group'", "'domain'"]) }} as entity_trait_id,
        event_id,
        'group' as entity_type,
        'domain' as identifier_type,
        domain as identifier_value,
        'domain' as trait_name,
        domain as trait_value,
        'gmail' as source,
        occurred_at,
        synced_at as _ingested_at
    from all_domains
    where domain is not null
)

select * from domain_traits
order by occurred_at desc

