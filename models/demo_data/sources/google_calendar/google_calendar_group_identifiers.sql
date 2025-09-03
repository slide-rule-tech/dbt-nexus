
WITH generic_domains AS (
    SELECT domain FROM UNNEST([
        'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 
        'aol.com', 'icloud.com', 'me.com', 'live.com', 'msn.com',
        'googlemail.com', 'ymail.com', 'rocketmail.com', 'protonmail.com',
        'mail.com', 'zoho.com'
    ]) as domain
),

organizer_domains AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.domain as identifier_value,
        'domain' as identifier_type
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.domain IS NOT NULL
    AND organizer.domain != ''
    AND organizer.domain NOT IN (SELECT domain FROM generic_domains)
),

creator_domains AS (
    SELECT 
        nexus_event_id as event_id,
        creator.domain as identifier_value,
        'domain' as identifier_type
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.domain IS NOT NULL
    AND creator.domain != ''
    AND creator.domain NOT IN (SELECT domain FROM generic_domains)
),

attendee_domains AS (
    SELECT
        base.nexus_event_id as event_id,
        attendee.domain as identifier_value,
        'domain' as identifier_type
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.domain IS NOT NULL
    AND attendee.domain != ''
    AND attendee.domain NOT IN (SELECT domain FROM generic_domains)
),

all_domains AS (
    SELECT * FROM organizer_domains
    UNION ALL
    SELECT * FROM creator_domains
    UNION ALL  
    SELECT * FROM attendee_domains
)

SELECT DISTINCT
    event_id,
    identifier_value,
    identifier_type
FROM all_domains