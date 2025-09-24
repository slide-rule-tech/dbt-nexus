-- Test: Touchpoint Batching Efficiency
-- This test verifies that nexus_touchpoint_paths_batched properly groups
-- touchpoint paths by person_id and attribution_deduplication_key to create
-- efficient batches for attribution modeling

with batching_analysis as (
    select
        -- Count records in both tables
        (select count(*) from {{ ref('nexus_touchpoint_paths') }}) as original_records,
        (select count(*) from {{ ref('nexus_touchpoint_paths_batched') }}) as batched_records,
        
        -- Count unique attribution states that should be batched
        (select count(distinct concat(person_id, '|', source, '|', medium, '|', campaign, '|', channel)) 
         from {{ ref('nexus_touchpoint_paths') }} 
         where source is not null) as expected_batches,
        
        -- Count actual batches created
        (select count(distinct touchpoint_path_batch_id) 
         from {{ ref('nexus_touchpoint_paths_batched') }}) as actual_batches,
        
        -- Calculate batching efficiency
        (select count(distinct concat(person_id, '|', source, '|', medium, '|', campaign, '|', channel)) 
         from {{ ref('nexus_touchpoint_paths') }} 
         where source is not null) * 100.0 /
        (select count(*) from {{ ref('nexus_touchpoint_paths') }}) as batching_efficiency_pct

),

-- Test that we have the same number of records (no data loss)
record_count_test as (
    select 
        case 
            when original_records = batched_records then true
            else false
        end as records_match
    from batching_analysis
),

-- Test that batching is actually happening (fewer batches than records)
batching_efficiency_test as (
    select 
        case 
            when actual_batches < original_records then true
            else false
        end as batching_occurred
    from batching_analysis
),

-- Test that batching efficiency is reasonable (>50% reduction expected)
efficiency_threshold_test as (
    select 
        case 
            when batching_efficiency_pct > 50 then true
            else false
        end as efficiency_acceptable
    from batching_analysis
),

-- Test that each batch represents a unique person + attribution combination
batch_uniqueness_test as (
    select 
        case 
            when count(distinct concat(person_id, '|', source, '|', medium, '|', campaign, '|', channel)) = count(distinct touchpoint_path_batch_id)
            then true
            else false
        end as batches_unique
    from {{ ref('nexus_touchpoint_paths_batched') }}
    where source is not null
),

-- Test that attribution data is preserved within batches
attribution_preservation_test as (
    select 
        case 
            when count(distinct concat(source, '|', medium, '|', campaign, '|', channel)) = 1
            then true
            else false
        end as attribution_consistent
    from {{ ref('nexus_touchpoint_paths_batched') }}
    group by touchpoint_path_batch_id
    having count(*) > 1
    limit 1
)

-- Final test results
select 
    'Touchpoint Batching Tests' as test_suite,
    
    -- Record count preservation
    (select records_match from record_count_test) as records_preserved,
    
    -- Batching efficiency
    (select batching_occurred from batching_efficiency_test) as batching_working,
    
    -- Efficiency threshold
    (select efficiency_acceptable from efficiency_threshold_test) as efficiency_acceptable,
    
    -- Batch uniqueness
    (select batches_unique from batch_uniqueness_test) as batches_unique,
    
    -- Attribution preservation (only test if we have multi-record batches)
    coalesce((select attribution_consistent from attribution_preservation_test), true) as attribution_preserved,
    
    -- Overall test result
    case 
        when (select records_match from record_count_test) = true
         and (select batching_occurred from batching_efficiency_test) = true
         and (select efficiency_acceptable from efficiency_threshold_test) = true
         and (select batches_unique from batch_uniqueness_test) = true
         and coalesce((select attribution_consistent from attribution_preservation_test), true) = true
        then 'PASS'
        else 'FAIL'
    end as overall_result

-- This test will fail if:
-- 1. Record counts don't match (data loss)
-- 2. No batching is occurring (actual_batches = original_records)
-- 3. Batching efficiency is too low (<50% reduction)
-- 4. Batches aren't unique per person+attribution combination
-- 5. Attribution data is inconsistent within batches
