# Migration Guide: v2 Entities & Relationships Architecture

## Overview

Version 2.0 introduces a unified entity-centric architecture that consolidates
person/group models and replaces rigid memberships with flexible relationships.

## Breaking Changes

### Removed Models

**Event Log (L3)**:

- ❌ `nexus_person_identifiers` → ✅ `nexus_entity_identifiers`
- ❌ `nexus_person_traits` → ✅ `nexus_entity_traits`
- ❌ `nexus_group_identifiers` → ✅ `nexus_entity_identifiers`
- ❌ `nexus_group_traits` → ✅ `nexus_entity_traits`
- ❌ `nexus_membership_identifiers` → ✅ `nexus_relationship_declarations`

**Identity Resolution (L4)**:

- ❌ `nexus_person_identifiers_edges` → ✅ `nexus_entity_identifiers_edges`
- ❌ `nexus_group_identifiers_edges` → ✅ `nexus_entity_identifiers_edges`
- ✅ `nexus_resolved_person_identifiers` (kept, now filters unified table)
- ✅ `nexus_resolved_group_identifiers` (kept, now filters unified table)
- ✅ `nexus_resolved_person_traits` (kept)
- ✅ `nexus_resolved_group_traits` (kept)

**Final Tables (L5)**:

- ❌ `nexus_persons` → ✅ `nexus_entities`
- ❌ `nexus_groups` → ✅ `nexus_entities`
- ❌ `nexus_memberships` → ✅ `nexus_relationships`
- ❌ `nexus_person_participants` → ✅ `nexus_entity_participants`
- ❌ `nexus_group_participants` → ✅ `nexus_entity_participants`

### Field Name Changes

| Old Field                  | New Field                     | Notes                        |
| -------------------------- | ----------------------------- | ---------------------------- |
| `person_id`                | `entity_id`                   | In entities table            |
| `group_id`                 | `entity_id`                   | In entities table            |
| `membership_id`            | `relationship_id`             | In relationships table       |
| `membership_identifier_id` | `relationship_declaration_id` | In declarations              |
| `person_identifier`        | `entity_a_identifier`         | In relationship declarations |
| `group_identifier`         | `entity_b_identifier`         | In relationship declarations |
| `person_id` (attribution)  | `entity_id`                   | In attribution models        |
| `person_participant_id`    | `entity_participant_id`       | In participants table        |

### New Required Fields

**Entity Models**:

- `entity_type`: STRING - Values: 'person', 'group', or custom types
- All entity identifiers and traits now include `entity_type` field

**Relationship Models**:

- `entity_a_type`: STRING - Entity type of entity A
- `entity_b_type`: STRING - Entity type of entity B
- `entity_a_role`: STRING - Role of entity A in relationship
- `entity_b_role`: STRING - Role of entity B in relationship
- `relationship_type`: STRING - Type of relationship (e.g., 'membership')
- `relationship_direction`: STRING - Values: 'bidirectional', 'a_to_b', 'b_to_a'

**Attribution Models**:

- `entity_id`: STRING - Entity identifier (replaces person_id)
- `entity_type`: STRING - Entity type ('person', 'group', etc.)

## Attribution Model Migration

### Before (Person-Only Attribution)

```sql
-- Old attribution models used person_id
SELECT
  person_id,
  attributed_event_id,
  attribution_model_name,
  source,
  medium
FROM nexus_attribution_model_results
WHERE person_id = 'per_12345'
```

### After (Multi-Entity Attribution)

```sql
-- New attribution models use entity_id + entity_type
SELECT
  entity_id,
  entity_type,
  attributed_event_id,
  attribution_model_name,
  source,
  medium
FROM nexus_attribution_model_results
WHERE entity_id = 'ent_12345' AND entity_type = 'person'

-- Or filter by entity type
SELECT * FROM nexus_attribution_model_results
WHERE entity_type = 'person'  -- Person-only attribution
```

**Key Changes:**

- All attribution models now support both person and group entities
- `person_id` → `entity_id` + `entity_type`
- Attribution timelines are separate for each entity type
- Can analyze cross-entity attribution relationships

## Source Model Migration

### Before (6 models per source)

```
models/sources/gmail/
  gmail_person_identifiers.sql
  gmail_person_traits.sql
  gmail_group_identifiers.sql
  gmail_group_traits.sql
  gmail_membership_identifiers.sql
  gmail_events.sql
```

### After (3 models per source)

```
models/sources/gmail/
  gmail_entity_identifiers.sql
  gmail_entity_traits.sql
  gmail_relationship_declarations.sql
  gmail_events.sql
```

### Source Model Structure

**Entity Identifiers** (`source_entity_identifiers.sql`):

```sql
-- Union person and group identifiers with entity_type field
WITH person_identifiers AS (
    SELECT
        {{ create_nexus_id('entity_identifier', [...]) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'person' as entity_type,  -- NEW: Required field
        'email' as identifier_type,
        email as identifier_value,
        'source' as source,
        occurred_at,
        _ingested_at,
        'role' as role  -- NEW: Required field
    FROM ...
),

group_identifiers AS (
    SELECT
        {{ create_nexus_id('entity_identifier', [...]) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'group' as entity_type,  -- NEW: Required field
        'domain' as identifier_type,
        domain as identifier_value,
        'source' as source,
        occurred_at,
        _ingested_at,
        'organization' as role  -- NEW: Required field
    FROM ...
)

SELECT * FROM person_identifiers
UNION ALL
SELECT * FROM group_identifiers
```

**Entity Traits** (`source_entity_traits.sql`):

```sql
-- Similar structure with entity_type field added
```

**Relationship Declarations** (`source_relationship_declarations.sql`):

```sql
SELECT
    {{ create_nexus_id('relationship_declaration', [...]) }} as relationship_declaration_id,
    event_id,
    occurred_at,

    -- Entity A (e.g., person)
    person_page_id as entity_a_identifier,
    'notion_id' as entity_a_identifier_type,
    'person' as entity_a_type,
    'contact' as entity_a_role,

    -- Entity B (e.g., group)
    org_page_id as entity_b_identifier,
    'notion_id' as entity_b_identifier_type,
    'group' as entity_b_type,
    'organization' as entity_b_role,

    -- Relationship metadata
    'membership' as relationship_type,
    'a_to_b' as relationship_direction,
    true as is_active,
    'source' as source
FROM ...
```

## Configuration Changes

### Before

```yaml
vars:
  sources:
    - name: notion
      events: true
      persons: true
      groups: true
      memberships: true
```

### After

```yaml
vars:
  nexus_entity_types: ["person", "group"] # NEW: Declare entity types

  sources:
    - name: notion
      events: true
      entities: ["person", "group"] # NEW: List entity types this source provides
      relationships: true # NEW: Replaces memberships
```

## Query Migration Examples

### Querying Persons

**Before**:

```sql
SELECT * FROM {{ ref('nexus_persons') }}
WHERE email = 'user@example.com'
```

**After**:

```sql
SELECT * FROM {{ ref('nexus_entities') }}
WHERE entity_type = 'person'
  AND email = 'user@example.com'
```

Or use the compatibility view:

```sql
SELECT * FROM {{ ref('persons') }}
WHERE email = 'user@example.com'
```

### Querying Memberships

**Before**:

```sql
SELECT
    m.membership_id,
    p.name as person_name,
    g.company_name
FROM {{ ref('nexus_memberships') }} m
JOIN {{ ref('nexus_persons') }} p ON m.person_id = p.person_id
JOIN {{ ref('nexus_groups') }} g ON m.group_id = g.group_id
```

**After**:

```sql
SELECT
    r.relationship_id,
    ea.name as person_name,
    eb.company_name
FROM {{ ref('nexus_relationships') }} r
JOIN {{ ref('nexus_entities') }} ea ON r.entity_a_id = ea.entity_id
JOIN {{ ref('nexus_entities') }} eb ON r.entity_b_id = eb.entity_id
WHERE r.relationship_type = 'membership'
  AND ea.entity_type = 'person'
  AND eb.entity_type = 'group'
```

Or use the compatibility view:

```sql
SELECT * FROM {{ ref('memberships') }}
```

### Querying Attribution Results

**Before**:

```sql
SELECT
  person_id,
  attribution_model_name,
  source,
  medium,
  campaign
FROM {{ ref('nexus_attribution_model_results') }}
WHERE person_id = 'per_12345'
```

**After**:

```sql
-- Person attribution
SELECT
  entity_id,
  attribution_model_name,
  source,
  medium,
  campaign
FROM {{ ref('nexus_attribution_model_results') }}
WHERE entity_id = 'ent_12345' AND entity_type = 'person'

-- Group attribution
SELECT
  entity_id,
  attribution_model_name,
  source,
  medium,
  campaign
FROM {{ ref('nexus_attribution_model_results') }}
WHERE entity_type = 'group'

-- Cross-entity attribution analysis
SELECT
  p.entity_id as person_id,
  g.entity_id as group_id,
  p.source as person_source,
  g.source as group_source
FROM {{ ref('nexus_attribution_model_results') }} p
JOIN {{ ref('nexus_attribution_model_results') }} g
  ON p.attributed_event_id = g.attributed_event_id
WHERE p.entity_type = 'person' AND g.entity_type = 'group'
```

## Custom Entity Types

To add custom entity types (e.g., `task`, `contract`), clients need to:

1. **Update configuration**:

```yaml
vars:
  nexus_entity_types: ["person", "group", "task"]

  sources:
    - name: notion
      entities: ["person", "group", "task"]
```

2. **Include tasks in source models**: Add task identifiers/traits to
   `notion_entity_identifiers.sql` and `notion_entity_traits.sql`

3. **Create custom identity resolution model**:

```sql
-- models/custom-entity-resolution/nexus_resolved_task_identifiers.sql
{{ config(materialized='table', tags=['identity-resolution', 'tasks']) }}

{{ nexus.resolve_identifiers('task', 'nexus_entity_identifiers', 'nexus_entity_identifiers_edges', var('nexus_max_recursion')) }}
```

4. **Add task relationships**: Include person→task or group→task relationships
   in `source_relationship_declarations.sql`

The `nexus_entities` table will automatically union the custom resolved task
identifiers!

## Backwards Compatibility

The migration includes compatibility views for a smoother transition:

- `persons` → filters `nexus_entities` WHERE `entity_type = 'person'`
- `groups` → filters `nexus_entities` WHERE `entity_type = 'group'`
- `memberships` → filters `nexus_relationships` WHERE
  `relationship_type = 'membership'`

These views maintain the old column names (person_id, group_id, membership_id)
for existing queries.

## Performance Improvements

**Unified Edges Table**:

- Before: 3 separate edge computations (person, group, deprecated entity)
- After: 1 unified edge computation, filtered by entity_type during resolution
- Result: 66% reduction in edge computation overhead

**Model Count Reduction**:

- Source layer: 6 models → 3 models (~50% reduction)
- Event log layer: 5 models → 3 models (~40% reduction)
- Simpler dependency graph, faster compilation

## Validation Checklist

After migration, verify:

- [ ] All source models compile without errors
- [ ] `nexus_entity_identifiers` contains data with `entity_type` field
- [ ] `nexus_entity_traits` contains data with `entity_type` field
- [ ] `nexus_entity_identifiers_edges` contains edges with `entity_type_a` and
      `entity_type_b`
- [ ] `nexus_resolved_person_identifiers` and `nexus_resolved_group_identifiers`
      produce expected entity IDs
- [ ] `nexus_entities` contains both persons and groups
- [ ] `nexus_relationships` contains resolved relationships with entity IDs
- [ ] `nexus_entity_participants` contains participants with entity_id and
      entity_type
- [ ] Attribution models (`nexus_touchpoint_paths`,
      `nexus_touchpoint_path_batches`) use entity_id and entity_type
- [ ] `nexus_attribution_model_results` contains attribution results for both
      person and group entities
- [ ] Client-facing views work correctly
- [ ] Downstream queries/dashboards updated to use new tables

## Support

For questions or issues with the migration, refer to the
[entities-and-relationships-rewrite.md](../to-dos/entities-and-relationships-rewrite.md)
architecture document.
