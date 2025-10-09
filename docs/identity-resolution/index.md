---
title: Identity Resolution Algorithm
tags: [explanation, identity-resolution, algorithm, performance]
summary:
  Complete technical explanation of the Nexus identity resolution algorithm,
  from source formatting through recursive resolution to final entity tables.
---

## Overview

The Nexus identity resolution algorithm transforms source-specific identifiers
into unified entities through a multi-step process. This document explains how
the algorithm works using the v0.3.0 entity-centric architecture, where all
entity types (persons, groups, custom entities) flow through a unified pipeline
before being resolved separately by `entity_type` for optimal performance.

This explanation covers the complete pipeline from raw source data to final
entity tables, with real performance metrics and data examples from production
usage.

## Algorithm Steps

### Step 0: Source Identifier Formatting (`*_entity_identifiers`)

**Purpose**: Transform source-specific data into the standardized Nexus
identifier format required by the algorithm. All you have to do to include a new
source in identity resolution is format your identifier data correctly here.

**Process**: Each source system creates a unified `*_entity_identifiers` table
that combines all entity types (persons, groups, etc.) with an `entity_type`
field. The `unpivot_identifiers` macro simplifies this process by automatically
converting columnar identifier data into the required row-based format.

**Required Schema**:

```sql
entity_identifier_id -- Unique identifier (ent_idfr_ prefix)
event_id            -- Links identifiers to specific events
edge_id             -- Groups identifiers that should be connected (typically event_id)
entity_type         -- Type of entity: 'person', 'group', etc.
identifier_type     -- The type of identifier (e.g., 'email', 'domain', 'location_id')
identifier_value    -- The actual identifier value
role                -- The entity's role in the event (optional)
occurred_at         -- Event timestamp (for metadata)
source              -- Source system name
```

**Example Implementation** (Gmail persons and groups):

```sql
-- models/sources/gmail/gmail_entity_identifiers.sql
{{ dbt_utils.union_relations([
    ref('gmail_message_person_identifiers'),
    ref('gmail_message_group_identifiers')
]) }}
```

This unions intermediate models that extract identifiers:

```sql
-- gmail_message_person_identifiers.sql (excerpt)
SELECT
    {{ nexus.create_nexus_id('entity_identifier', ['event_id', 'sender.email', "'person'", "'sender'"]) }} as entity_identifier_id,
    event_id,
    event_id as edge_id,
    'person' as entity_type,
    'email' as identifier_type,
    sender.email as identifier_value,
    'sender' as role,
    occurred_at,
    'gmail' as source
FROM gmail_message_events
WHERE sender.email IS NOT NULL
```

**Output Data** (unified entity identifiers):

```sql
entity_identifier_id         | event_id           | edge_id            | entity_type | identifier_type | identifier_value      | role          | occurred_at | source
ent_idfr_a1b2c3d4...         | evt_gmail_123...   | evt_gmail_123...   | person      | email           | john@company.com      | sender        | 2025-01-20  | gmail
ent_idfr_e5f6g7h8...         | evt_gmail_123...   | evt_gmail_123...   | group       | domain          | company.com           | sender_domain | 2025-01-20  | gmail
ent_idfr_i9j0k1l2...         | evt_notion_456...  | evt_notion_456...  | person      | email           | john@company.com      | contact       | 2025-01-21  | notion
```

**Key Parameters**:

- `model_name`: Source table containing the raw identifier data
- `event_id`: Used for generating participant tables after identity resolution
- `columns`: List of identifier columns to unpivot
- `edge_id_field`: Field used to group identifiers (often `event_id` if only one
  person or groups for an event. If there are multiple participants in an event,
  usually event_id + identifiers does well.)
- `role_column`: Specifies the entity's role in events
- `additional_columns`: Metadata to preserve (timestamps, source info)

**Result**: Standardized identifier format that can be automatically processed
by the identity resolution algorithm.

### Step 1: Source Identifier Collection (`nexus_entity_identifiers`)

**Purpose**: Union all entity identifiers from different source systems into a
single table containing all entity types.

**Process**: The `process_entity_identifiers()` macro collects identifiers from
all enabled sources that have entity identifier models (`*_entity_identifiers`).

**Example Data** (from Lobbie appointments):

```sql
-- Source: lobbie_group_identifiers
event_id                                | identifier_type                    | identifier_value                        | role
evt_lobbie_5794cc43e896d7b21673bf1f8e... | location_id                        | 1190                                   | location
evt_lobbie_5794cc43e896d7b21673bf1f8e... | location_lobbie_integration_uuid   | 5b283546-34c3-4d80-9c56-3cb9a8636f19  | location
evt_lobbie_bbfc0469c015233a40475fc6... | location_id                        | 339                                    | location
evt_lobbie_bbfc0469c015233a40475fc6... | location_lobbie_integration_uuid   | 2d08a33b-d1d6-4bf8-9ce0-d6d416ba5c79  | location
```

**Result**: 3.6M identifier records from 1.8M appointment events, representing
395 unique locations.

### Step 2: Edge Creation (`nexus_group_identifiers_edges`)

**Purpose**: Create connections between identifiers that should be resolved to
the same entity.

**Process**: The `create_identifier_edges('nexus_group_identifiers')` macro:

1. **Raw Edge Generation**: Joins identifiers that share the same `edge_id`
   (typically `event_id`)
2. **Edge Deduplication**: Uses surrogate keys on identifier types and value to
   generate uniqueness. Use uniqueness to eliminate duplicate edges for
   performance
3. **Output**: Unique identifier pairs that represent the same entity

**Algorithm Details**:

```sql
-- Step 2a: Generate raw edges
SELECT
  a.identifier_type as identifier_type_a,
  a.identifier_value as identifier_value_a,
  b.identifier_type as identifier_type_b,
  b.identifier_value as identifier_value_b,
  generate_surrogate_key([
    a.identifier_type, a.identifier_value,
    b.identifier_type, b.identifier_value
  ]) as edge_uniqueness_hash
FROM nexus_group_identifiers a
JOIN nexus_group_identifiers b
  ON a.edge_id = b.edge_id  -- Same edge
  AND (a.identifier_type != b.identifier_type OR a.identifier_value != b.identifier_value)

-- Step 2b: Deduplicate edges
SELECT DISTINCT identifier_type_a, identifier_value_a, identifier_type_b, identifier_value_b
FROM raw_edges
```

**Edge Deduplication Impact**:

- **Before deduplication**: ~1.8M duplicate edges (one per event mentioning each
  location)
- **After deduplication**: 790 unique edges (395 locations × 2 identifier types
  each)
- **Performance improvement**: 3.99s vs hours of processing

**Example Edges**:

```sql
identifier_type_a                   | identifier_value_a                      | identifier_type_b  | identifier_value_b
location_lobbie_integration_uuid   | 5b283546-34c3-4d80-9c56-3cb9a8636f19   | location_id        | 1190
location_lobbie_integration_uuid   | 2d08a33b-d1d6-4bf8-9ce0-d6d416ba5c79   | location_id        | 339
location_lobbie_integration_uuid   | f3fcd059-3572-469b-847b-653a7cc65239   | location_id        | 630
```

### Step 3: Recursive Resolution (`nexus_resolved_group_identifiers`)

**Purpose**: Use connected components algorithm to group all related identifiers
under a single entity ID.

**Process**: The
`resolve_identifiers('group', 'nexus_group_identifiers', 'nexus_group_identifiers_edges', 3)`
macro implements a recursive CTE with these phases:

#### Phase 3a: Recursive Component Discovery

```sql
WITH RECURSIVE recursive_components AS (
  -- Base case: Every identifier starts as its own component
  SELECT DISTINCT
    identifier_type as component_identifier_type,
    identifier_value as component_identifier_value,
    identifier_type,
    identifier_value,
    identifier_type || ':' || identifier_value as path,
    0 as recursion_level
  FROM nexus_group_identifiers

  UNION ALL

  -- Recursive case: Walk to connected identifiers
  SELECT
    rc.component_identifier_type,
    rc.component_identifier_value,
    e.identifier_type_b as identifier_type,
    e.identifier_value_b as identifier_value,
    rc.path || '|' || e.identifier_type_b || ':' || e.identifier_value_b as path,
    rc.recursion_level + 1
  FROM recursive_components rc
  JOIN nexus_group_identifiers_edges e
    ON rc.identifier_type = e.identifier_type_a
   AND rc.identifier_value = e.identifier_value_a
  WHERE NOT CONTAINS(rc.path, e.identifier_type_b || ':' || e.identifier_value_b)
    AND rc.recursion_level < 3  -- Max recursion limit
)
```

#### Phase 3b: Component Assignment

```sql
-- Assign each identifier to the lexicographically first identifier in its component
SELECT
  identifier_type,
  identifier_value,
  generate_surrogate_key([
    first_value(component_identifier_type) OVER(...),
    first_value(component_identifier_value) OVER(...)
  ]) as group_id
FROM recursive_components
```

**Example Resolution**:

```sql
-- Before resolution (separate identifiers):
identifier_type                    | identifier_value                        | group_id
location_id                        | 1190                                   | NULL
location_lobbie_integration_uuid   | 5b283546-34c3-4d80-9c56-3cb9a8636f19  | NULL

-- After resolution (unified entity):
identifier_type                    | identifier_value                        | group_id
location_id                        | 1190                                   | 1433a23518736e48ab9b2eff2af17544
location_lobbie_integration_uuid   | 5b283546-34c3-4d80-9c56-3cb9a8636f19  | 1433a23518736e48ab9b2eff2af17544
```

**Result**: 790 resolved identifiers representing 395 unique groups (2
identifiers per group).

### Step 4: Final Entity Table (`nexus_groups`)

**Purpose**: Create the final groups table with consolidated entity information.

**Process**: The `finalize_entity('group')` macro:

1. **Entity Consolidation**: Groups all identifiers by `group_id`
2. **Metadata Enrichment**: Adds creation timestamps, processing flags
3. **Deduplication**: Ensures one record per unique entity

**Example Groups**:

```sql
group_id                          | created_at           | existing_group
1433a23518736e48ab9b2eff2af17544 | 2025-01-20 12:45:20 | true
02124e742dda060ddbf750f8c385c3bf | 2025-01-20 12:45:20 | true
8341287f3c3f47ff97dc105df9d16b9b | 2025-01-20 12:45:20 | true
```

### Step 5: Event Participation (`nexus_group_participants`)

**Purpose**: Link resolved entities back to the original events for
participation tracking.

**Process**: The `finalize_participants('group')` macro:

1. **Event Mapping**: Connects each event to its resolved group entity
2. **Role Preservation**: Maintains the original role information from Step 0
3. **Participation Records**: Creates event-to-entity links with role context

**Algorithm**:

```sql
SELECT
  generate_surrogate_key([group_id, event_id]) as group_participant_id,
  event_id,
  group_id
FROM nexus_group_identifiers gi
JOIN nexus_resolved_group_identifiers rgi
  ON gi.identifier_type = rgi.identifier_type
 AND gi.identifier_value = rgi.identifier_value
```

**Example Participations**:

```sql
event_id                                | group_id                          | events_for_this_group
evt_lobbie_5794cc43e896d7b21673bf1f8e... | 1433a23518736e48ab9b2eff2af17544 | 10,180
evt_lobbie_bbfc0469c015233a40475fc6... | 02124e742dda060ddbf750f8c385c3bf | 24,974
evt_lobbie_39065a39e20208106fa5151d... | 8341287f3c3f47ff97dc105df9d16b9b | 21,719
```

**Result**: 1,806,682 participation records (one per event) linking events to
395 resolved location groups.

**Role Information**: Each participation record preserves the role specified in
Step 0 (`'location'` in this example), enabling queries like:

- "Find all events where entity X participated as a location"
- "Get all appointment events at specific locations"
- "Analyze entity participation patterns by role type"

**Role Examples**:

- **Groups**: `'location'`, `'venue'`, `'department'`, `'organization'`
- **Persons**: `'patient'`, `'provider'`, `'contact'`, `'assignee'`
- **Memberships**: `'member_of'`, `'employed_by'`, `'enrolled_in'`

## Algorithm Performance

### Scalability Characteristics

**Linear Components**:

- Source identifier collection: O(n) where n = number of events
- Final entity creation: O(g) where g = number of unique entities
- Event participation: O(n) where n = number of events

**Optimized Components**:

- Edge creation: O(u) where u = number of unique edges (after deduplication)
- Recursive resolution: O(u × d) where d = maximum recursion depth (3)

### Performance Metrics (Lobbie Groups Example)

| Step                 | Records In       | Records Out         | Processing Time | Optimization            |
| -------------------- | ---------------- | ------------------- | --------------- | ----------------------- |
| Source Collection    | 3.6M events      | 3.6M identifiers    | ~15s            | Table materialization   |
| Edge Creation        | 3.6M identifiers | 790 edges           | 3.99s           | **Deduplication**       |
| Recursive Resolution | 790 edges        | 790 resolved        | 4.91s           | Limited recursion depth |
| Final Entities       | 790 resolved     | 395 groups          | ~3s             | Component consolidation |
| Event Participation  | 3.6M + 790       | 1.8M participations | 3.32s           | Efficient joins         |

### Edge Deduplication Benefits

**Problem**: Without deduplication, high-frequency entities create massive edge
explosion:

- Location with 26,000 events → 26,000² = 676M duplicate edges
- Total system edges: Billions of redundant connections

**Solution**: Surrogate key-based deduplication:

- Unique edge identification using
  `generate_surrogate_key([type_a, value_a, type_b, value_b])`
- Elimination of duplicate edges while preserving all unique relationships
- Performance improvement: Hours → Seconds

**Impact**:

- **Edge reduction**: 1.8M → 790 unique edges (99.96% reduction)
- **Memory efficiency**: Linear memory usage vs quadratic explosion
- **Processing speed**: Recursive algorithm operates on minimal edge set

## Algorithm Guarantees

### Correctness Properties

1. **Completeness**: All source identifiers are processed and resolved
2. **Consistency**: Identical entities receive identical group IDs across runs
3. **Transitivity**: If A connects to B and B connects to C, then A, B, C share
   the same group ID
4. **Event Preservation**: Every original event maintains its connection to
   resolved entities

### Data Integrity Constraints

1. **Unique Entity IDs**: Each resolved entity has exactly one group ID
2. **Bidirectional Resolution**: All identifier types within a group resolve to
   the same entity
3. **Event Mapping**: Every event connects to exactly one entity per identifier
   type
4. **Temporal Consistency**: Entity resolution is deterministic and reproducible

## Extension to Other Entity Types

This same algorithm applies to:

- **Persons**: `*_person_identifiers` → `nexus_persons` +
  `nexus_person_participants`
- **Memberships**: `*_membership_identifiers` → `nexus_memberships`

The only differences are:

- Source table patterns (`*_person_identifiers` vs `*_group_identifiers`)
- Entity-specific finalization logic
- Role and relationship semantics

The core edge creation, recursive resolution, and deduplication logic remains
identical across all entity types.

## Related Documentation

- **[How-to: Add New Source](../how-to/add-new-source.md)** - Step-by-step guide
  for implementing Step 0
- **[Reference: Identity Resolution Models](../reference/models/identity-resolution.md)** -
  API details for all models
- **[Reference: Entity Resolution Macros](../reference/macros/entity-resolution.md)** -
  Macro documentation and parameters
- **[How-to: Configure Identity Resolution](../how-to/configure-identity-resolution.md)** -
  Configuration options and tuning
- **[Explanation: Performance Considerations](./performance.md)** - Detailed
  performance analysis and optimization strategies
- **[Reference: Database Schema](../reference/database-schema.md)** - Complete
  schema documentation for all tables
