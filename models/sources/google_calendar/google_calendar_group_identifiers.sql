
{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}
WITH organizer_domains AS (
    SELECT 
        nexus_event_id as event_id,
        {{ dbt_utils.generate_surrogate_key(['nexus_event_id', 'organizer.domain']) }} as edge_id,
        organizer.domain as identifier_value,
        'domain' as identifier_type,
        'organizer_domain' as role,
        'google_calendar' as source,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE {{ filter_non_generic_domains('organizer.domain') }}
),

creator_domains AS (
    SELECT 
        nexus_event_id as event_id,
        {{ dbt_utils.generate_surrogate_key(['nexus_event_id', 'creator.domain']) }} as edge_id,
        creator.domain as identifier_value,
        'domain' as identifier_type,
        'creator_domain' as role,
        'google_calendar' as source,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE {{ filter_non_generic_domains('creator.domain') }}
),

attendee_domains AS (
    SELECT
        base.nexus_event_id as event_id,
        {{ dbt_utils.generate_surrogate_key(['base.nexus_event_id', 'attendee.domain']) }} as edge_id,
        attendee.domain as identifier_value,
        'domain' as identifier_type,
        CASE 
            WHEN attendee.is_optional = true THEN 'optional_attendee_domain'
            ELSE 'attendee_domain'
        END as role,
        'google_calendar' as source,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE {{ filter_non_generic_domains('attendee.domain') }}
),

all_domains AS (
    SELECT * FROM organizer_domains
    UNION ALL
    SELECT * FROM creator_domains
    UNION ALL  
    SELECT * FROM attendee_domains
)

SELECT 
    event_id,
    edge_id,
    identifier_type,
    identifier_value,
    role,
    occurred_at,
    source
FROM all_domains
ORDER BY event_id DESC
