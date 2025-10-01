# Fix resolve_traits Macro Bug

## Issue Description

The `resolve_traits` macro has a bug where not all traits are being joined back
to persons in the final `nexus_persons` table.

## Root Cause

The `resolve_traits` macro uses an **INNER JOIN** between traits and entity
identifiers:

```sql
joined_traits as (
    select
        g.person_id,
        t.trait_name,
        t.trait_value,
        t.occurred_at
    from traits t
    join entity_identifiers g  -- This INNER JOIN is the problem
        on t.identifier_type = g.identifier_type
        and t.identifier_value = g.identifier_value
),
```

This means that if a person ID exists in the `nexus_resolved_person_identifiers`
table but has no matching traits in the source data, they get **completely
excluded** from the `nexus_resolved_person_traits` table.

## Impact

1. **Missing Person Records**: Person IDs that exist in identifiers but have no
   traits don't appear in the final `nexus_persons` table
2. **Incomplete Data**: Even if a person has some traits, they might be missing
   other expected traits
3. **Data Inconsistency**: The final table has fewer records than expected

## Symptoms

- `nexus_resolved_person_identifiers` has more unique person IDs than
  `nexus_resolved_person_traits`
- Some person IDs appear in the final table with NULL values for traits that
  should exist
- Email addresses that should appear in both GHL and Segment records only appear
  in one

## Proposed Fix

Change the INNER JOIN to a LEFT JOIN in the `resolve_traits` macro:

```sql
joined_traits as (
    select
        g.person_id,
        t.trait_name,
        t.trait_value,
        t.occurred_at
    from entity_identifiers g
    left join traits t  -- Change to LEFT JOIN
        on t.identifier_type = g.identifier_type
        and t.identifier_value = g.identifier_value
),
```

This ensures that all resolved person IDs get trait records, even if they have
no traits in the source data.

## Testing

After implementing the fix:

1. Verify that `nexus_resolved_person_identifiers` and
   `nexus_resolved_person_traits` have the same number of unique person IDs
2. Check that all person IDs in the final table have the expected traits
   populated
3. Confirm that email addresses appear consistently across all person records
   that should have them

## Status

- **Identified**: ✅
- **Root Cause Found**: ✅
- **Fix Proposed**: ✅
- **Implementation**: ⏳ Pending
