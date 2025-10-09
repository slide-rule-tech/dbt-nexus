{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'group_identifiers']
) }}

-- Extract group (domain) identifiers from gmail messages
with gmail_messages as (
    select * from {{ ref('gmail_messages') }}
),

-- Extract domains from sender emails (excluding generic domains)
sender_domains as (
    select 
        event_id,
        occurred_at,
        synced_at,
        sender.domain as domain,
        'sender_domain' as role
    from gmail_messages
    where sender.domain is not null
      and not sender.generic_domain
),

-- Extract domains from recipient emails (excluding generic domains)
recipient_domains as (
    select 
        event_id,
        occurred_at,
        synced_at,
        recipient.domain as domain,
        'recipient_domain' as role
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

-- Create domain identifiers (generic domains already filtered upstream)
domain_identifiers as (
    select 
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'domain', "'group'", 'role', 'occurred_at']) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        domain as identifier_value,
        'gmail' as source,
        occurred_at,
        synced_at as _ingested_at,
        role
    from all_domains
    where domain is not null
      and domain not like '%>%'
),

-- Add redirected domains (www. versions of email domains)
redirected_domains as (
    select 
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', nexus.redirected_domain('domain'), "'group'", 'role', 'occurred_at']) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        {{ nexus.redirected_domain('domain') }} as identifier_value,
        'gmail' as source,
        occurred_at,
        synced_at as _ingested_at,
        role
    from all_domains
    where domain is not null
      and domain not like '%>%'
)

select * from domain_identifiers
union all
select * from redirected_domains
order by occurred_at desc

