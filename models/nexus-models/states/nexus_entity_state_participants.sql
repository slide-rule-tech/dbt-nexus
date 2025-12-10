{{ config(
    materialized='table',
    cluster_by=['event_id'],
    tags=['states', 'entity-state-participants']
) }}

-- Nexus Entity State Participants
-- Links events to entity_states based on active state at event time
-- Only includes events within the date spine range for performance
-- Only includes events where entity has an active state

{# Get date spine range from config (same as entity_states_events will use) #}
{% set start_date = var('nexus.state_snapshots.start_date', (modules.datetime.date.today() - modules.datetime.timedelta(days=365)).strftime('%Y-%m-%d')) %}
{% set end_date = modules.datetime.date.today().strftime('%Y-%m-%d') %}

-- For regular events: Find active state at event time
-- Only process events within date spine range for performance
WITH events_with_entities AS (
    SELECT DISTINCT
        e.event_id,
        ep.entity_id,
        ep.entity_type,
        e.occurred_at
    FROM {{ ref('nexus_events') }} e
    INNER JOIN {{ ref('nexus_entity_participants') }} ep ON e.event_id = ep.event_id
    WHERE DATE(e.occurred_at) >= '{{ start_date }}'
        AND DATE(e.occurred_at) <= '{{ end_date }}'
),

-- Find active entity_state for each event
-- Tie handling: If event occurs exactly when state changes (occurred_at = valid_from),
-- use the PREVIOUS state (strictly less than ensures initial state wins)
active_states AS (
    SELECT 
        ewe.event_id,
        ewe.entity_id,
        ewe.entity_type,
        es.entity_state_id,
        ROW_NUMBER() OVER (
            PARTITION BY ewe.event_id
            ORDER BY es.valid_from DESC
        ) as state_rank
    FROM events_with_entities ewe
    INNER JOIN {{ ref('nexus_entity_states') }} es
        ON ewe.entity_id = es.entity_id
        AND es.valid_from < ewe.occurred_at  -- Strictly before (ties → initial state)
        AND (es.valid_to IS NULL OR es.valid_to >= ewe.occurred_at)
)

SELECT 
    event_id,
    entity_state_id,
    entity_id,
    entity_type
FROM active_states
WHERE state_rank = 1

