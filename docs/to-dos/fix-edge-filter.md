# Fix Identity Resolution Edge Filtering Performance Issue

## Problem

Identity resolution was experiencing catastrophic performance degradation in
BigQuery (20K+ CPU seconds, exceeding the 5.1K limit). This was introduced in
commit `1245851` when refactoring from separate person/group models to unified
entities.

**Root Cause**: The `resolve_identifiers` macros were not filtering edges by
`entity_type` during recursive graph traversal, causing person resolution to
traverse into group identity graphs and vice versa.

### Why This Worked Before

**Before commit `1245851`:**

- Separate `nexus_person_identifiers_edges` table (only person edges)
- Separate `nexus_group_identifiers_edges` table (only group edges)
- No cross-contamination possible

**After commit `1245851`:**

- Unified `nexus_entity_identifiers_edges` table (all edges together)
- Resolution models filtered identifiers by entity_type but NOT edges
- Cross-entity edges explored during traversal (person→person AND person→group)

**Result**: 4x more edges explored than necessary, causing massive performance
degradation.

## Solution

Added entity type filtering to the edge joins in the recursive CTE of both
BigQuery and Snowflake `resolve_identifiers` macros.

### Changes Made

**File**: `macros/entity-resolution/bigquery__resolve_identifiers.sql` (lines
34-35)

```sql
join {{ ref(edges_table) }} e
  on rc.identifier_type  = e.identifier_type_a
 and rc.identifier_value = e.identifier_value_a
 and e.entity_type_a = '{{ entity_type }}'  -- NEW
 and e.entity_type_b = '{{ entity_type }}'  -- NEW
```

**File**: `macros/entity-resolution/snowflake__resolve_identifiers.sql` (lines
31-32)

```sql
join {{ ref(edges_table) }} e
  on rc.identifier_type  = e.identifier_type_a
 and rc.identifier_value = e.identifier_value_a
 and e.entity_type_a = '{{ entity_type }}'  -- NEW
 and e.entity_type_b = '{{ entity_type }}'  -- NEW
```

This ensures that:

- When resolving `person` identifiers, only person→person edges are traversed
- When resolving `group` identifiers, only group→group edges are traversed
- Cross-entity edges (from relationship declarations) are excluded from identity
  resolution

## Expected Impact

- **Performance**: Reduce CPU usage from 20K+ seconds to <5K seconds (likely
  <1K)
- **Graph Size**: Reduce edges explored by ~75% (4x → 1x necessary edges)
- **Correctness**: Maintain proper entity type isolation
- **No Data Impact**: This doesn't change the edges themselves, only which edges
  are traversed during resolution

## Technical Details

The `create_identifier_edges` macro correctly creates edges with `entity_type_a`
and `entity_type_b` columns. The fix ensures that the resolution macros filter
on these fields during the recursive graph traversal.

The recursive CTE structure is safe for BigQuery's recursive CTE restrictions
because:

- The recursive CTE is at the top level of the WITH clause
- It references `{{ ref() }}` tables directly (which compile to table
  references, not CTEs)
- The entity_type filters are just WHERE conditions on the existing table
  reference

## Validation

After the fix:

1. Run
   `dbt compile --select nexus_resolved_person_identifiers nexus_resolved_group_identifiers`
2. Check compiled SQL contains the new entity_type filters on lines ~34-35 in
   the recursive CTE
3. Run the models in BigQuery and verify CPU usage is under 5K seconds
4. Verify entity counts remain correct (no cross-contamination between persons
   and groups)

## Related

- Migration guide: `docs/migrations/v2-entities-relationships.md`
- Architecture docs: `docs/overview/architecture.md`
- Original commit: `1245851` (feat: switch to entities and relationships
  [WORK-2456])
