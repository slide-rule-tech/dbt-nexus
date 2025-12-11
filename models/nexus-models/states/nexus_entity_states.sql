{{ config(
    materialized='table',
    cluster_by=['entity_id', 'valid_from'],
    tags=['states', 'entity-states']
) }}

-- Nexus Entity States Model
-- Pivots nexus_states into a single table with all states as columns
-- One row per state change (when any state changes, create new row)
-- 
-- To add new states: Add a new MAX(CASE...) line in the pivoted_states CTE
-- The column name should match the state_name value from nexus_states

WITH nexus_states_data AS (
    SELECT * FROM {{ ref('nexus_states') }}
),

-- Get all unique state change timestamps per entity
-- A change occurs when any state is entered or exited
state_change_timestamps AS (
    SELECT DISTINCT
        entity_id,
        entity_type,
        state_entered_at as change_timestamp
    FROM nexus_states_data
    
    UNION DISTINCT
    
    SELECT DISTINCT
        entity_id,
        entity_type,
        state_exited_at as change_timestamp
    FROM nexus_states_data
    WHERE state_exited_at IS NOT NULL
),

-- Get state values at each change timestamp
-- For each entity-timestamp combination, get the active value of each state
state_values_at_timestamps AS (
    SELECT
        sct.entity_id,
        sct.entity_type,
        sct.change_timestamp,
        ns.state_name,
        ns.state_value,
        ROW_NUMBER() OVER (
            PARTITION BY sct.entity_id, sct.change_timestamp, ns.state_name
            ORDER BY ns.state_entered_at DESC
        ) as state_rank
    FROM state_change_timestamps sct
    INNER JOIN nexus_states_data ns
        ON sct.entity_id = ns.entity_id
        AND ns.state_entered_at <= sct.change_timestamp
        AND (ns.state_exited_at IS NULL OR ns.state_exited_at > sct.change_timestamp)
    WHERE ns.state_value IS NOT NULL
),

-- Pivot states into columns
-- Each state_name becomes a column with its state_value
pivoted_states_raw AS (
    SELECT
        svat.entity_id,
        svat.entity_type,
        svat.change_timestamp,
        svat.state_name,
        svat.state_value
    FROM state_values_at_timestamps svat
    WHERE svat.state_rank = 1
),

-- Pivot: Convert state_name rows into columns
-- Add new states by adding MAX(CASE WHEN state_name = 'new_state' THEN state_value END) as new_state,
pivoted_states AS (
    SELECT
        entity_id,
        entity_type,
        change_timestamp as valid_from,
        MAX(CASE WHEN state_name = 'lead' THEN state_value END) as lead
        -- Add more states here as they are added to nexus_states
        -- Example: , MAX(CASE WHEN state_name = 'billing_lifecycle' THEN state_value END) as billing_lifecycle
    FROM pivoted_states_raw
    GROUP BY entity_id, entity_type, change_timestamp
),

-- Calculate valid_to (next change timestamp for this entity)
states_with_valid_to AS (
    SELECT
        ps.*,
        LEAD(valid_from) OVER (
            PARTITION BY entity_id
            ORDER BY valid_from
        ) as valid_to
    FROM pivoted_states ps
),

-- Add entity_state_id first
with_state_ids AS (
    SELECT
        {{ nexus.create_nexus_id('entity_state', ['entity_id', 'valid_from']) }} as entity_state_id,
        entity_id,
        entity_type,
        lead,
        -- Add more state columns here matching pivoted_states
        valid_from,
        valid_to
    FROM states_with_valid_to
),

-- Add previous_entity_state_id and is_current flag
final AS (
    SELECT
        entity_state_id,
        entity_id,
        entity_type,
        lead,
        -- Add more state columns here matching pivoted_states
        valid_from,
        valid_to,
        CASE
            WHEN valid_to IS NULL THEN TRUE
            ELSE FALSE
        END as is_current,
        LAG(entity_state_id) OVER (
            PARTITION BY entity_id
            ORDER BY valid_from
        ) as previous_entity_state_id
    FROM with_state_ids
)

SELECT * FROM final

