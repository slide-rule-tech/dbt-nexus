{{ config(
    materialized='table',
    cluster_by=['entity_id', 'valid_from'],
    tags=['states', 'entity-states']
) }}

-- depends_on: {{ ref('nexus_states') }}

{# Discover dimensions and measurements from nexus_states at compile time #}
{% set dimension_names = [] %}
{% set measurement_names = [] %}
{% if execute %}
    {% set dim_query %}
        select distinct state_name
        from {{ ref('nexus_states') }}
        where state_category = 'dimension' or state_category is null
        order by state_name
    {% endset %}
    {% set dimension_names = run_query(dim_query).columns[0].values() %}

    {% set msr_query %}
        select distinct state_name
        from {{ ref('nexus_states') }}
        where state_category = 'measurement'
        order by state_name
    {% endset %}
    {% set measurement_names = run_query(msr_query).columns[0].values() %}
{% endif %}

{% set all_state_names = dimension_names + measurement_names %}

{% if all_state_names | length > 0 %}

WITH nexus_states_data AS (
    SELECT * FROM {{ ref('nexus_states') }}
),

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

state_values_at_timestamps AS (
    SELECT
        sct.entity_id,
        sct.entity_type,
        sct.change_timestamp,
        ns.state_name,
        ns.state_value,
        ns.state_numeric_value,
        ns.state_category,
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
        OR ns.state_numeric_value IS NOT NULL
),

pivoted_states_raw AS (
    SELECT
        entity_id,
        entity_type,
        change_timestamp,
        state_name,
        state_value,
        state_numeric_value,
        state_category
    FROM state_values_at_timestamps
    WHERE state_rank = 1
),

pivoted_states AS (
    SELECT
        entity_id,
        entity_type,
        change_timestamp as valid_from,
        {% for dim in dimension_names %}
        MAX(CASE WHEN state_name = '{{ dim }}' THEN state_value END) as {{ dim }},
        {% endfor %}
        {% for msr in measurement_names %}
        MAX(CASE WHEN state_name = '{{ msr }}' THEN state_numeric_value END) as {{ msr }}{{ "," if not loop.last }}
        {% endfor %}
    FROM pivoted_states_raw
    GROUP BY entity_id, entity_type, change_timestamp
),

states_with_valid_to AS (
    SELECT
        ps.*,
        LEAD(valid_from) OVER (
            PARTITION BY entity_id
            ORDER BY valid_from
        ) as valid_to
    FROM pivoted_states ps
),

with_state_ids AS (
    SELECT
        {{ nexus.create_nexus_id('entity_state', ['entity_id', 'valid_from']) }} as entity_state_id,
        entity_id,
        entity_type,
        {% for dim in dimension_names %}
        {{ dim }},
        {% endfor %}
        {% for msr in measurement_names %}
        {{ msr }},
        {% endfor %}
        valid_from,
        valid_to
    FROM states_with_valid_to
),

final AS (
    SELECT
        entity_state_id,
        entity_id,
        entity_type,
        {% for dim in dimension_names %}
        {{ dim }},
        {% endfor %}
        {% for msr in measurement_names %}
        {{ msr }},
        {{ msr }} - COALESCE(LAG({{ msr }}) OVER (
            PARTITION BY entity_id
            ORDER BY valid_from
        ), 0) as {{ msr }}_delta,
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
