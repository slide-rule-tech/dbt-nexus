{{ config(materialized='table', tags=['realtime', 'identity-resolution', 'groups']) }}

WITH 
-- Get new identifiers from the event
new_identifiers AS (
    SELECT *
    FROM {{ ref(var('realtime_group_identifiers_model')) }} -- DIRECTIVE: inject alasql sql table=source_group_identifiers
    where identifier_value is not null
),

-- Combined lookup of existing identifiers and their status
identifier_lookup AS (
    SELECT
        n.row_id,
        n.identifier_type,
        n.identifier_value,
        r.group_id,
        CASE WHEN r.group_id IS NULL THEN TRUE ELSE FALSE END AS is_new_identifier
    FROM new_identifiers n
    
    LEFT JOIN {{ ref('resolved_group_identifiers') }} r {{ directives('retain_original_reference') }}
        ON CAST(n.identifier_type as string) = CAST(r.identifier_type as string)
        AND CAST(n.identifier_value as string) = CAST(r.identifier_value as string)
),

-- Group identifiers by row_id and find any existing group_ids associated with them
row_group_ids AS (
    SELECT
        n.row_id,
        MIN(il.group_id) AS min_group_id
    FROM new_identifiers n
    LEFT JOIN identifier_lookup il
        ON CAST(n.identifier_type as string) = CAST(il.identifier_type as string)
        AND CAST(n.identifier_value as string) = CAST(il.identifier_value as string)
        AND il.group_id IS NOT NULL
    GROUP BY n.row_id
),

-- Generate final assignment - either use min existing group_id or create new
final_assignment AS (
    SELECT
        n.row_id,
        CASE
            WHEN r.min_group_id IS NOT NULL THEN r.min_group_id
            ELSE {{ dbt_utils.generate_surrogate_key(['n.row_id', 'current_timestamp()']) }}
        END AS group_id,
        CASE
            WHEN r.min_group_id IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS existing_group
    FROM (SELECT DISTINCT row_id FROM new_identifiers) n
    LEFT JOIN row_group_ids r
        ON n.row_id = r.row_id
),

-- Result with all identifiers and assigned group_id
result AS (
    SELECT
        n.*,
        f.group_id,
        f.existing_group,
        il.is_new_identifier
    FROM new_identifiers n
    JOIN final_assignment f ON n.row_id = f.row_id
    JOIN identifier_lookup il ON n.row_id = il.row_id 
        AND CAST(n.identifier_type as string) = CAST(il.identifier_type as string)
        AND CAST(n.identifier_value as string) = CAST(il.identifier_value as string)
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['group_id', 'identifier_type', 'identifier_value']) }} as identifier_id,
    group_id,
    event_id,
    identifier_type,
    identifier_value,
    is_new_identifier AS realtime_processed,
    existing_group
FROM result 