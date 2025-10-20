{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'relationship_declarations']
) }}

-- Extract person→group relationships from Google Calendar events
WITH google_calendar_event_events AS (
    SELECT * FROM {{ ref('google_calendar_event_events') }}
),

-- Organizer→domain relationships
organizer_memberships AS (
    SELECT
        event_id,
        occurred_at,
        
        -- Entity A (person - organizer)
        organizer.email as entity_a_identifier,
        'email' as entity_a_identifier_type,
        'person' as entity_a_type,
        'member' as entity_a_role,
        
        -- Entity B (group - domain)
        organizer.domain as entity_b_identifier,
        'domain' as entity_b_identifier_type,
        'group' as entity_b_type,
        'organization' as entity_b_role,
        
        -- Relationship metadata
        'membership' as relationship_type,
        'a_to_b' as relationship_direction,
        true as is_active,
        'google_calendar' as source
    FROM google_calendar_event_events
    WHERE organizer.email IS NOT NULL
      AND organizer.domain IS NOT NULL
      AND organizer.domain NOT IN (
          {%- for domain in var('email_domain_groups_exclude_list', []) -%}
          '{{ domain }}'
          {%- if not loop.last -%},{%- endif -%}
          {%- endfor -%}
      )
),

-- Creator→domain relationships
creator_memberships AS (
    SELECT
        event_id,
        occurred_at,
        
        -- Entity A (person - creator)
        creator.email as entity_a_identifier,
        'email' as entity_a_identifier_type,
        'person' as entity_a_type,
        'member' as entity_a_role,
        
        -- Entity B (group - domain)
        creator.domain as entity_b_identifier,
        'domain' as entity_b_identifier_type,
        'group' as entity_b_type,
        'organization' as entity_b_role,
        
        -- Relationship metadata
        'membership' as relationship_type,
        'a_to_b' as relationship_direction,
        true as is_active,
        'google_calendar' as source
    FROM google_calendar_event_events
    WHERE creator.email IS NOT NULL
      AND creator.domain IS NOT NULL
      AND creator.domain NOT IN (
          {%- for domain in var('email_domain_groups_exclude_list', []) -%}
          '{{ domain }}'
          {%- if not loop.last -%},{%- endif -%}
          {%- endfor -%}
      )
),

-- Attendee→domain relationships
attendee_memberships AS (
    SELECT
        event_id,
        occurred_at,
        
        -- Entity A (person - attendee)
        attendee.email as entity_a_identifier,
        'email' as entity_a_identifier_type,
        'person' as entity_a_type,
        'member' as entity_a_role,
        
        -- Entity B (group - domain)
        attendee.domain as entity_b_identifier,
        'domain' as entity_b_identifier_type,
        'group' as entity_b_type,
        'organization' as entity_b_role,
        
        -- Relationship metadata
        'membership' as relationship_type,
        'a_to_b' as relationship_direction,
        true as is_active,
        'google_calendar' as source
    FROM google_calendar_event_events,
    UNNEST(attendees) as attendee
    WHERE attendee.email IS NOT NULL
      AND attendee.domain IS NOT NULL
      AND attendee.domain NOT IN (
          {%- for domain in var('email_domain_groups_exclude_list', []) -%}
          '{{ domain }}'
          {%- if not loop.last -%},{%- endif -%}
          {%- endfor -%}
      )
),

all_memberships AS (
    SELECT * FROM organizer_memberships
    UNION ALL
    SELECT * FROM creator_memberships
    UNION ALL
    SELECT * FROM attendee_memberships
),

-- Deduplicate in case attendees array has duplicates
deduplicated AS (
    SELECT DISTINCT
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
    FROM all_memberships
)

SELECT 
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
FROM deduplicated
ORDER BY occurred_at DESC

