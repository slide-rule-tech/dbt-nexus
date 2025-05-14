{{ config(materialized='table', tags=['realtime']) }}

WITH new_identifiers AS (
    
    SELECT
     *
    FROM {{ ref(var('realtime_person_identifiers_model')) }} -- DIRECTIVE: inject alasql sql table=source_person_identifiers
    where identifier_value is not null
),

-- Combined lookup of existing identifiers and their status
identifier_lookup AS (
    SELECT
        n.row_id,
        n.identifier_type,
        n.identifier_value,
        r.person_id,
        CASE WHEN r.person_id IS NULL THEN TRUE ELSE FALSE END AS is_new_identifier
    FROM new_identifiers n
    
    LEFT JOIN {{ ref('resolved_person_identifiers') }} r
        ON CAST(n.identifier_type as string) = CAST(r.identifier_type as string)
        AND CAST(n.identifier_value as string) = CAST(r.identifier_value as string)
),

-- Group identifiers by row_id and find any existing person_ids associated with them
row_person_ids AS (
    SELECT
        n.row_id,
        MIN(il.person_id) AS min_person_id
    FROM new_identifiers n
    LEFT JOIN identifier_lookup il
        ON n.identifier_type = il.identifier_type
        AND n.identifier_value = il.identifier_value
        AND il.person_id IS NOT NULL
    GROUP BY n.row_id
),

-- Generate final assignment - either use min existing person_id or create new
final_assignment AS (
    SELECT
        n.row_id,
        CASE
            WHEN r.min_person_id IS NOT NULL THEN r.min_person_id
            ELSE {{ dbt_utils.generate_surrogate_key(['n.row_id']) }}
        END AS person_id,
        CASE
            WHEN r.min_person_id IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS existing_person
    FROM (SELECT DISTINCT row_id FROM new_identifiers) n
    LEFT JOIN row_person_ids r
        ON n.row_id = r.row_id
),

-- Result with all identifiers and assigned person_id
result AS (
    SELECT
        n.*,
        f.person_id,
        f.existing_person,
        il.is_new_identifier
    FROM new_identifiers n
    JOIN final_assignment f ON n.row_id = f.row_id
    JOIN identifier_lookup il ON n.row_id = il.row_id 
        AND CAST(n.identifier_type as string) = CAST(il.identifier_type as string)
        AND CAST(n.identifier_value as string) = CAST(il.identifier_value as string)
)

SELECT DISTINCT
    {{ dbt_utils.generate_surrogate_key(['person_id', 'identifier_type', 'identifier_value']) }} as identifier_id,
    person_id,
    event_id,
    identifier_type,
    identifier_value,
    is_new_identifier AS realtime_processed,
    existing_person
FROM result