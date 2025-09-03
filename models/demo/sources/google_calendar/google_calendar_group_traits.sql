
WITH generic_domains AS (
    SELECT domain FROM UNNEST([
        'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 
        'aol.com', 'icloud.com', 'me.com', 'live.com', 'msn.com',
        'googlemail.com', 'ymail.com', 'rocketmail.com', 'protonmail.com',
        'mail.com', 'zoho.com'
    ]) as domain
),

organizer_domain_traits AS (
    SELECT 
        nexus_event_id as event_id,
        organizer.domain as group_identifier,
        'domain' as identifier_type,
        'domain' as trait_name,
        organizer.domain as trait_value
    FROM {{ ref('google_calendar_events_base') }}
    WHERE organizer.domain IS NOT NULL
    AND organizer.domain != ''
    AND organizer.domain NOT IN (SELECT domain FROM generic_domains)
    
),

creator_domain_traits AS (
    SELECT 
        nexus_event_id as event_id,
        creator.domain as group_identifier,
        'domain' as identifier_type,
        'domain' as trait_name,
        creator.domain as trait_value
    FROM {{ ref('google_calendar_events_base') }}
    WHERE creator.domain IS NOT NULL
    AND creator.domain != ''
    AND creator.domain NOT IN (SELECT domain FROM generic_domains)
),

attendee_domain_traits AS (
    SELECT
        base.nexus_event_id as event_id,
        attendee.domain as group_identifier,
        'domain' as identifier_type,
        'domain' as trait_name,
        attendee.domain as trait_value
    FROM {{ ref('google_calendar_events_base') }} base,
    UNNEST(base.attendees) as attendee
    WHERE attendee.domain IS NOT NULL
    AND attendee.domain != ''
    AND attendee.domain NOT IN (SELECT domain FROM generic_domains)
    
    
   
),

all_traits AS (
    SELECT * FROM organizer_domain_traits
    UNION ALL
    SELECT * FROM creator_domain_traits
    UNION ALL
    SELECT * FROM attendee_domain_traits
)

SELECT DISTINCT
    event_id,
    group_identifier,
    identifier_type,
    trait_name,
    trait_value
FROM all_traits