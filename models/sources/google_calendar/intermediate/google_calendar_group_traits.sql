{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['nexus', 'google_calendar', 'intermediate', 'group_traits']
) }}

-- Extract group (domain) traits from Google Calendar events
WITH google_calendar_event_events AS (
    SELECT * FROM {{ ref('google_calendar_event_events') }}
),

organizer_domain_traits AS (
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'organizer.domain', "'group'", "'domain_name'", "'organizer_domain'"]) }} as entity_trait_id,
        event_id,
        'group' as entity_type,
        'domain' as identifier_type,
        organizer.domain as identifier_value,
        'name' as trait_name,
        organizer.domain as trait_value,
        'organizer_domain' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events
    WHERE organizer.domain IS NOT NULL
    AND organizer.domain NOT IN (
        {%- for domain in var('email_domain_groups_exclude_list', []) -%}
        '{{ domain }}'
        {%- if not loop.last -%},{%- endif -%}
        {%- endfor -%}
    )
),

creator_domain_traits AS (
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'creator.domain', "'group'", "'domain_name'", "'creator_domain'"]) }} as entity_trait_id,
        event_id,
        'group' as entity_type,
        'domain' as identifier_type,
        creator.domain as identifier_value,
        'name' as trait_name,
        creator.domain as trait_value,
        'creator_domain' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events
    WHERE creator.domain IS NOT NULL
    AND creator.domain NOT IN (
        {%- for domain in var('email_domain_groups_exclude_list', []) -%}
        '{{ domain }}'
        {%- if not loop.last -%},{%- endif -%}
        {%- endfor -%}
    )
),

attendee_domain_traits AS (
    SELECT
        {{ nexus.create_nexus_id('entity_trait', ['event_id', 'attendee.domain', "'group'", "'domain_name'", "'attendee_domain'"]) }} as entity_trait_id,
        event_id,
        'group' as entity_type,
        'domain' as identifier_type,
        attendee.domain as identifier_value,
        'name' as trait_name,
        attendee.domain as trait_value,
        'attendee_domain' as role,
        'google_calendar' as source,
        occurred_at,
        _ingested_at
    FROM google_calendar_event_events,
    UNNEST(attendees) as attendee
    WHERE attendee.domain IS NOT NULL
    AND attendee.domain NOT IN (
        {%- for domain in var('email_domain_groups_exclude_list', []) -%}
        '{{ domain }}'
        {%- if not loop.last -%},{%- endif -%}
        {%- endfor -%}
    )
),

-- Deduplicate in case attendees array has duplicates
deduplicated AS (
    SELECT DISTINCT
        entity_trait_id,
        event_id,
        entity_type,
        identifier_type,
        identifier_value,
        trait_name,
        trait_value,
        role,
        source,
        occurred_at,
        _ingested_at
    FROM (
        SELECT * FROM organizer_domain_traits
        UNION ALL
        SELECT * FROM creator_domain_traits
        UNION ALL
        SELECT * FROM attendee_domain_traits
    )
)

SELECT * FROM deduplicated
WHERE trait_value IS NOT NULL
ORDER BY occurred_at DESC

