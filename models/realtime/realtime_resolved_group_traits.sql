{{ config(materialized='table', tags=['realtime', 'identity-resolution', 'groups']) }}

WITH new_traits AS (
    SELECT *
    FROM {{ ref(var('realtime_group_traits_model')) }} -- DIRECTIVE: inject alasql sql table=source_group_traits
    where trait_value is not null
),

resolved_identifiers AS (
    SELECT 
        group_id,
        identifier_type,
        identifier_value
    FROM {{ ref('realtime_resolved_group_identifiers') }} -- DIRECTIVE: inject alasql sql table=realtime_resolved_group_identifiers
),

-- Join traits with group IDs
traits_with_group_id AS (
    SELECT
        r.group_id,
        t.*
    FROM new_traits t
    JOIN resolved_identifiers r
        ON CAST(t.identifier_type as string) = CAST(r.identifier_type as string)
        AND CAST(t.identifier_value as string) = CAST(r.identifier_value as string)
),

-- Get distinct group_ids to filter existing traits
relevant_group_ids AS (
    SELECT DISTINCT
        group_id
    FROM traits_with_group_id
),

-- Get only the relevant existing latest trait values
existing_traits AS (
    SELECT
        e.group_id,
        e.trait_name,
        e.trait_value,
        e.occurred_at
    FROM {{ ref('resolved_group_traits') }} e  {{ directives('retain_original_reference') }}
    INNER JOIN relevant_group_ids g
        ON e.group_id = g.group_id
),

final_traits AS (
    -- Compare and set to_update flag
    SELECT
        t.group_id,
        t.identifier_type,
        t.identifier_value,
        t.trait_name,
        t.trait_value,
        t.occurred_at,
        -- Set to_update=true if:
        -- 1. No existing trait for this group/trait_name OR
        -- 2. New trait is more recent AND has a different value
        CASE
            WHEN e.group_id IS NULL THEN TRUE -- New trait
            WHEN t.occurred_at > e.occurred_at AND t.trait_value != e.trait_value THEN TRUE -- Updated trait
            ELSE FALSE -- Not an update
        END AS to_update
    FROM traits_with_group_id t
    LEFT JOIN existing_traits e
        ON t.group_id = e.group_id
        AND t.trait_name = e.trait_name
)

SELECT distinct
    {{ dbt_utils.generate_surrogate_key(['group_id', 'trait_name', 'trait_value']) }} as trait_id,
    group_id,
    trait_name,
    trait_value,
    occurred_at,
    true as realtime_processed
FROM final_traits
WHERE to_update = true 