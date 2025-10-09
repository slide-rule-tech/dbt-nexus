# Nexus v2.0.0 - Entities & Relationships Architecture

## Release Date

TBD

## Overview

Version 2.0.0 is a **major architectural rewrite** that introduces a unified
entity-centric architecture. This release consolidates person/group models into
unified entity models and replaces rigid memberships with flexible entity
relationships.

## Breaking Changes

### Removed Models (11 total)

**Event Log (L3)**:

- `nexus_person_identifiers` → `nexus_entity_identifiers`
- `nexus_person_traits` → `nexus_entity_traits`
- `nexus_group_identifiers` → `nexus_entity_identifiers`
- `nexus_group_traits` → `nexus_entity_traits`
- `nexus_membership_identifiers` → `nexus_relationship_declarations`

**Identity Resolution (L4)**:

- `nexus_person_identifiers_edges` → `nexus_entity_identifiers_edges`
- `nexus_group_identifiers_edges` → `nexus_entity_identifiers_edges`

**Final Tables (L5)**:

- `nexus_persons` → `nexus_entities`
- `nexus_groups` → `nexus_entities`
- `nexus_memberships` → `nexus_relationships`
- `nexus_person_participants` (removed)
- `nexus_group_participants` (removed)

### Field Name Changes

| Old Field                  | New Field                     | Context                      |
| -------------------------- | ----------------------------- | ---------------------------- |
| `person_id`                | `entity_id`                   | In entities table            |
| `group_id`                 | `entity_id`                   | In entities table            |
| `membership_id`            | `relationship_id`             | In relationships table       |
| `membership_identifier_id` | `relationship_declaration_id` | In declarations              |
| `person_identifier`        | `entity_a_identifier`         | In relationship declarations |
| `group_identifier`         | `entity_b_identifier`         | In relationship declarations |

### New Required Fields

**All entity models now include**:

- `entity_type`: STRING - Values: 'person', 'group', or custom types

**Relationship models include**:

- `entity_a_type`, `entity_b_type`: Entity types
- `entity_a_role`, `entity_b_role`: Roles in relationship
- `relationship_type`: Type of relationship
- `relationship_direction`: 'bidirectional', 'a_to_b', or 'b_to_a'

### Configuration Changes

**Before**:

```yaml
vars:
  sources:
    - name: your_source
      events: true
      persons: true
      groups: true
      memberships: true
```

**After**:

```yaml
vars:
  nexus_entity_types: ["person", "group"]

  sources:
    - name: your_source
      events: true
      entities: ["person", "group"]
      relationships: true
```

### New ID Prefixes

- `ent_idfr_` - Entity identifiers (replaces `per_idfr_` and `grp_idfr_` in
  unified models)
- `ent_tr_` - Entity traits (replaces `per_tr_` and `grp_tr_` in unified models)
- `rel_decl_` - Relationship declarations (replaces `mem_` prefix for
  memberships)
- `rel_` - Final relationships

## New Features

### 1. Unified Entity Architecture

All entities (persons, groups, custom types) now flow through unified models:

- Single `nexus_entity_identifiers` table for all entity types
- Single `nexus_entity_traits` table for all entity types
- Single `nexus_entity_identifiers_edges` table computed once
- Final `nexus_entities` table with `entity_type` field

### 2. Universal Relationships

Flexible relationship system replaces rigid memberships:

- Any entity type can relate to any other entity type
- Explicit roles for both sides of the relationship
- Directional relationships (bidirectional, one-way)
- Extensible relationship types

### 3. Custom Entity Type Support

Easy to extend with custom entity types (task, contract, product, etc.):

```sql
-- Client project adds one boilerplate model per custom type
-- models/custom-entity-resolution/nexus_resolved_task_identifiers.sql
{{ nexus.resolve_identifiers('task', 'nexus_entity_identifiers', 'nexus_entity_identifiers_edges', var('nexus_max_recursion')) }}
```

The `nexus_entities` table automatically unions all configured entity types!

### 4. Optimized Identity Resolution

- **Single edges computation** for all entity types (was 3 separate
  computations)
- **Parallel resolution** by entity type for performance
- **Efficient filtering** using WHERE entity_type = 'person' in recursive CTEs
- **66% reduction** in edge computation overhead

## Performance Improvements

### Model Count Reduction

**Source Layer**: 6 models → 4 models per source (~33% reduction)

- Combines person/group identifiers → entity_identifiers
- Combines person/group traits → entity_traits
- Replaces membership_identifiers → relationship_declarations

**Event Log Layer**: 5 models → 4 models (~20% reduction)

- Unified entity models eliminate redundant person/group models

**Final Tables**: 5 models → 2 models (60% reduction)

- Single entities table replaces persons + groups
- Single relationships table replaces memberships + participants

### Computation Efficiency

- **Edges**: Computed once instead of 3x (person, group, deprecated entity)
- **Traits**: Single join to all identifiers instead of 2 separate joins + union
- **Simpler DAG**: Fewer dependencies, faster compilation

## Migration Guide

See
[docs/migrations/v2-entities-relationships.md](migrations/v2-entities-relationships.md)
for complete migration guide.

### Quick Migration Checklist

Source models need to be updated:

- [ ] Create `{source}_entity_identifiers.sql` (union person + group)
- [ ] Create `{source}_entity_traits.sql` (union person + group)
- [ ] Create `{source}_relationship_declarations.sql` (replace memberships)
- [ ] Delete old person/group/membership models
- [ ] Update `dbt_project.yml` configuration
- [ ] Test full pipeline

## Backwards Compatibility

Compatibility views are provided for a smoother transition:

- `persons` view → filters `nexus_entities WHERE entity_type = 'person'`
- `groups` view → filters `nexus_entities WHERE entity_type = 'group'`
- `memberships` view → filters
  `nexus_relationships WHERE relationship_type = 'membership'`

These views maintain old column names (person_id, group_id, membership_id).

## Updated Documentation

- ✅ Migration guide created
- ✅ Source model structure guide updated
- ✅ Create source models guide updated
- ✅ Template sources documentation updated
- ✅ Development workflow guide updated
- ✅ Schema documentation cleaned up

## Validation Results

Tested with Notion source in slide_rule_tech client project:

- ✅ 323 entity identifiers (242 person + 81 group)
- ✅ 525 entity traits
- ✅ 304 unified edges
- ✅ 146 resolved entities (110 person + 36 group)
- ✅ 62 active relationships
- ✅ All models compile and run successfully
- ✅ End-to-end pipeline validated

## Contributors

- Architecture design and implementation
- Notion source migration and testing
- Documentation updates

## Next Steps

- [ ] Migrate Gmail template source
- [ ] Migrate Google Calendar template source
- [ ] Migrate Segment template source
- [ ] Update attribution models for new architecture
- [ ] Create examples for custom entity types
- [ ] Performance benchmarking vs v1

## Support

For questions about this release:

- See [Migration Guide](migrations/v2-entities-relationships.md)
- See [Architecture Doc](to-dos/entities-and-relationships-rewrite.md)
- Review updated source documentation in `docs/sources/`
