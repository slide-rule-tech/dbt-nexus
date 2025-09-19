{{ config(
    enabled=var('nexus', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}
WITH organizer_identifiers AS (
    SELECT 
        nexus_event_id as event_id,
        {{ dbt_utils.generate_surrogate_key(['nexus_event_id', 'organizer.email']) }} as edge_id,
        organizer.email as identifier_value,
        'email' as identifier_type,
        'organizer' as role,
        'google_calendar' as source,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.email IS NOT NULL
    AND organizer.email != ''
),

creator_identifiers AS (
    SELECT 
        nexus_event_id as event_id,
        {{ dbt_utils.generate_surrogate_key(['nexus_event_id', 'creator.email']) }} as edge_id,
        creator.email as identifier_value,
        'email' as identifier_type,
        'creator' as role,
        'google_calendar' as source,
        start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.email IS NOT NULL
    AND creator.email != ''
),

attendee_identifiers AS (
    SELECT
        base.nexus_event_id as event_id,
        {{ dbt_utils.generate_surrogate_key(['base.nexus_event_id', 'attendee.email']) }} as edge_id,  
        attendee.email as identifier_value,
        'email' as identifier_type,
        CASE 
            WHEN attendee.is_optional = true THEN 'optional_attendee'
            ELSE 'attendee'
        END as role,
        'google_calendar' as source,
        base.start_time as occurred_at
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.email IS NOT NULL
    AND attendee.email != ''
),

all_identifiers AS (
    SELECT * FROM organizer_identifiers
    UNION ALL
    SELECT * FROM creator_identifiers  
    UNION ALL
    SELECT * FROM attendee_identifiers
)

SELECT 
    event_id,
    edge_id,
    identifier_type,
    identifier_value,
    role,
    occurred_at,
    source
FROM all_identifiers
ORDER BY event_id DESC
