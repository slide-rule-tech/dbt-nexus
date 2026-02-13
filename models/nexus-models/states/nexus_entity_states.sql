{{ config(
    materialized='table',
    cluster_by=['entity_id', 'valid_from'],
    tags=['states', 'entity-states']
) }}

-- Nexus Entity States Model
-- Pivots nexus_states into a single table with all states as columns
-- One row per state change (when any state changes, create new row)
--
-- State columns are discovered dynamically from nexus_states at compile time.
-- No manual edits needed when new states are added.

-- depends_on: {{ ref('nexus_states') }}

{# Discover distinct state_name values from nexus_states at compile time #}
{% set state_names = [] %}
{% if execute %}
    {% set state_names_query %}
        select distinct state_name from {{ ref('nexus_states') }} order by state_name
    {% endset %}
    {% set state_names = run_query(state_names_query).columns[0].values() %}
{% endif %}

{% if state_names | length > 0 %}

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

-- Pivot: Convert state_name rows into columns (dynamically generated)
pivoted_states AS (
    SELECT
        entity_id,
        entity_type,
        change_timestamp as valid_from,
        {% for state_name in state_names %}
        MAX(CASE WHEN state_name = '{{ state_name }}' THEN state_value END) as {{ state_name }}{{ "," if not loop.last }}
        {% endfor %}
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
        {% for state_name in state_names %}
        {{ state_name }},
        {% endfor %}
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
        {% for state_name in state_names %}
        {{ state_name }},
        {% endfor %}
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

{% else %}

-- No states configured - return empty result set
-- FROM (SELECT 1) provides a row source; WHERE 1=0 filters to zero rows (BigQuery requires FROM for WHERE)
SELECT
    CAST(NULL AS STRING) as entity_state_id,
    CAST(NULL AS STRING) as entity_id,
    CAST(NULL AS STRING) as entity_type,
    CAST(NULL AS TIMESTAMP) as valid_from,
    CAST(NULL AS TIMESTAMP) as valid_to,
    CAST(NULL AS BOOLEAN) as is_current,
    CAST(NULL AS STRING) as previous_entity_state_id
FROM (SELECT 1)
WHERE 1 = 0

{% endif %}
