with timeline as (
    -- First get the person ID for the specified email
    with person as (
        select person_id
        from {{ ref('nexus_persons') }}
        where email = 'kevin@kevincmclaughlin.com'
    ),
    
    -- Get all event IDs this person participated in
    person_events as (
        select pp.event_id
        from {{ ref('nexus_person_participants') }} pp
        inner join person p on pp.person_id = p.person_id
    )
    
    -- Get the actual event details
    select 
        e.id,
        e.occurred_at,
        e.event_name,
        e.event_description,
        e.value,
        e.value_unit,
        e.event_type,
        e.source
    from {{ ref('nexus_events') }} e
    inner join person_events pe on e.id = pe.event_id
    order by e.occurred_at desc
)

select * from timeline