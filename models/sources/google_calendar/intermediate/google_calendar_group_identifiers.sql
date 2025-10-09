{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'group_identifiers']
) }}

-- Extract group (domain) identifiers from Google Calendar events
WITH google_calendar_event_events AS (
    SELECT * FROM {{ ref('google_calendar_event_events') }}
),

organizer_domains AS (
    SELECT 
        event_id,
        occurred_at,
        _ingested_at,
        organizer.domain as domain,
        'organizer_domain' as role
    FROM google_calendar_event_events
    WHERE organizer.domain IS NOT NULL
    AND organizer.domain != ''
    AND organizer.domain NOT IN (
        {%- for domain in var('email_domain_groups_exclude_list') -%}
        '{{ domain }}'
        {%- if not loop.last -%},{%- endif -%}
        {%- endfor -%}
    )
),

creator_domains AS (
    SELECT 
        event_id,
        occurred_at,
        _ingested_at,
        creator.domain as domain,
        'creator_domain' as role
    FROM google_calendar_event_events
    WHERE creator.domain IS NOT NULL
    AND creator.domain != ''
    AND creator.domain NOT IN (
        {%- for domain in var('email_domain_groups_exclude_list') -%}
        '{{ domain }}'
        {%- if not loop.last -%},{%- endif -%}
        {%- endfor -%}
    )
),

attendee_domains AS (
    SELECT 
        event_id,
        occurred_at,
        _ingested_at,
        attendee.domain as domain,
        'attendee_domain' as role
    FROM google_calendar_event_events,
    UNNEST(attendees) as attendee
    WHERE attendee.domain IS NOT NULL
    AND attendee.domain != ''
    AND attendee.domain NOT IN (
        {%- for domain in var('email_domain_groups_exclude_list') -%}
        '{{ domain }}'
        {%- if not loop.last -%},{%- endif -%}
        {%- endfor -%}
    )
),

-- Union all domains (use DISTINCT to avoid duplicate domain per event)
all_domains AS (
    SELECT * FROM organizer_domains
    UNION DISTINCT
    SELECT * FROM creator_domains
    UNION DISTINCT
    SELECT * FROM attendee_domains
),

-- Create domain identifiers (generic domains already filtered upstream)
domain_identifiers AS (
    SELECT 
        {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'domain', "'group'", 'role']) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        domain as identifier_value,
        'google_calendar' as source,
        occurred_at,
        _ingested_at,
        role
    FROM all_domains
    WHERE domain IS NOT NULL
    AND domain NOT LIKE '%>%'
)

SELECT 
    entity_identifier_id,
    event_id,
    edge_id,
    entity_type,
    identifier_type,
    identifier_value,
    source,
    occurred_at,
    _ingested_at,
    role
FROM domain_identifiers
WHERE identifier_value IS NOT NULL
ORDER BY occurred_at DESC

