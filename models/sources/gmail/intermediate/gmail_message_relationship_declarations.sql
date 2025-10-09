{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('enabled', false),
    materialized='table',
    tags=['gmail', 'intermediate', 'relationship_declarations']
) }}

-- Extract person→group relationships from gmail messages
with gmail_message_events as (
    select * from {{ ref('gmail_message_events') }}
),

-- Sender→domain relationships
sender_memberships as (
    select
        event_id,
        occurred_at,
        
        -- Entity A (person - sender)
        sender.email as entity_a_identifier,
        'email' as entity_a_identifier_type,
        'person' as entity_a_type,
        'member' as entity_a_role,
        
        -- Entity B (group - domain)
        sender.domain as entity_b_identifier,
        'domain' as entity_b_identifier_type,
        'group' as entity_b_type,
        'organization' as entity_b_role,
        
        -- Relationship metadata
        'membership' as relationship_type,
        'a_to_b' as relationship_direction,
        true as is_active,
        'gmail' as source
    from gmail_message_events
    where sender.email is not null
      and sender.domain is not null
      and not sender.generic_domain
),

-- Recipient→domain relationships
recipient_memberships as (
    select
        event_id,
        occurred_at,
        
        -- Entity A (person - recipient)
        recipient.email as entity_a_identifier,
        'email' as entity_a_identifier_type,
        'person' as entity_a_type,
        'member' as entity_a_role,
        
        -- Entity B (group - domain)
        recipient.domain as entity_b_identifier,
        'domain' as entity_b_identifier_type,
        'group' as entity_b_type,
        'organization' as entity_b_role,
        
        -- Relationship metadata
        'membership' as relationship_type,
        'a_to_b' as relationship_direction,
        true as is_active,
        'gmail' as source
    from gmail_message_events,
    unnest(recipients) as recipient
    where recipient.email is not null
      and recipient.domain is not null
      and not recipient.generic_domain
),

all_memberships as (
    select * from sender_memberships
    union all
    select * from recipient_memberships
),

-- Deduplicate in case recipients array has duplicates
deduplicated as (
    select distinct
        event_id,
        occurred_at,
        entity_a_identifier,
        entity_a_identifier_type,
        entity_a_type,
        entity_a_role,
        entity_b_identifier,
        entity_b_identifier_type,
        entity_b_type,
        entity_b_role,
        relationship_type,
        relationship_direction,
        is_active,
        source
    from all_memberships
)

select 
    {{ nexus.create_nexus_id('relationship_declaration', ['event_id', 'entity_a_identifier', 'entity_b_identifier', 'entity_a_role', 'occurred_at']) }} as relationship_declaration_id,
    event_id,
    occurred_at,
    entity_a_identifier,
    entity_a_identifier_type,
    entity_a_type,
    entity_a_role,
    entity_b_identifier,
    entity_b_identifier_type,
    entity_b_type,
    entity_b_role,
    relationship_type,
    relationship_direction,
    is_active,
    source
from deduplicated
order by occurred_at desc

