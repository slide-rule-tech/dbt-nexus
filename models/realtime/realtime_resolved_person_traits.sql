{{ config(materialized='table', tags=['realtime']) }}

WITH new_traits AS (
    SELECT *
    FROM {{ ref(var('realtime_person_traits_model')) }} -- DIRECTIVE: inject alasql sql table=source_person_traits
    where trait_value is not null
),

resolved_identifiers AS (
    SELECT 
        person_id,
        identifier_type,
        identifier_value
    FROM {{ ref('realtime_resolved_person_identifiers') }}-- DIRECTIVE: inject alasql sql table=realtime_resolved_person_identifiers
),

-- Join traits with person IDs
traits_with_person_id AS (
    SELECT
        r.person_id,
        t.*
    FROM new_traits t
    JOIN resolved_identifiers r
        ON CAST(t.identifier_type as string) = CAST(r.identifier_type as string)
        AND CAST(t.identifier_value as string) = CAST(r.identifier_value as string)
),

-- Get distinct person_ids to filter existing traits
relevant_person_ids AS (
    SELECT DISTINCT
        person_id
    FROM traits_with_person_id
),

-- Get only the relevant existing latest trait values
existing_traits AS (
    SELECT
        e.person_id,
        e.trait_name,
        e.trait_value,
        e.occurred_at
    FROM {{ ref('resolved_person_traits') }} e  {{ directives('retain_original_reference') }}
    INNER JOIN relevant_person_ids p
        ON e.person_id = p.person_id
),

final_traits AS (
    -- Compare and set to_update flag
    SELECT
        t.person_id,
        t.identifier_type,
        t.identifier_value,
        t.trait_name,
        t.trait_value,
        t.occurred_at,
        -- Set to_update=true if:
        -- 1. No existing trait for this person/trait_name OR
        -- 2. New trait is more recent AND has a different value
        CASE
            WHEN e.person_id IS NULL THEN TRUE -- New trait
            WHEN t.occurred_at > e.occurred_at AND t.trait_value != e.trait_value THEN TRUE -- Updated trait
            ELSE FALSE -- Not an update
        END AS to_update
    FROM traits_with_person_id t
    LEFT JOIN existing_traits e
        ON t.person_id = e.person_id
        AND t.trait_name = e.trait_name
)

SELECT distinct
    {{ dbt_utils.generate_surrogate_key(['person_id', 'trait_name', 'trait_value']) }} as trait_id,
    person_id,
    trait_name,
    trait_value,
    occurred_at,
    true as realtime_processed
FROM final_traits
where to_update = true