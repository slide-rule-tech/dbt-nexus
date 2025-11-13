---
title: Relationships Metadata
tags: [metadata, relationships, entities, reference]
summary: Metadata table providing distinct relationship types, entity types, and directions from nexus_relationships
---

The `nexus_relationships_metadata` table provides a catalog of all distinct relationship configurations present in the `nexus_relationships` table. This metadata table helps you understand what types of relationships exist between different entity types.

## Overview

This metadata table aggregates distinct combinations of relationship types, entity types, and relationship directions, making it easy to:

- Discover available relationship types
- Understand which entity types can have relationships
- Identify relationship directions (a_to_b, b_to_a, bidirectional)
- Track relationship patterns across your data

## Schema

| Field                  | Type   | Description                                          |
| ---------------------- | ------ | ---------------------------------------------------- |
| `relationship_type`    | String | The type of relationship (membership, etc.)          |
| `entity_a_type`        | String | The type of entity A (person or group)               |
| `entity_b_type`        | String | The type of entity B (person or group)               |
| `relationship_direction`| String | The direction of the relationship (a_to_b, etc.)     |

## Query Examples

### Discover All Available Relationships

```sql
select
    relationship_type,
    entity_a_type,
    entity_b_type,
    relationship_direction
from {{ ref('nexus_relationships_metadata') }}
order by relationship_type, entity_a_type, entity_b_type
```

### Find Relationships by Type

```sql
select
    entity_a_type,
    entity_b_type,
    relationship_direction
from {{ ref('nexus_relationships_metadata') }}
where relationship_type = 'membership'
order by entity_a_type, entity_b_type
```

### Count Relationships by Type

```sql
select
    relationship_type,
    count(*) as relationship_configurations
from {{ ref('nexus_relationships_metadata') }}
group by relationship_type
order by relationship_configurations desc
```

### Find Relationships Between Specific Entity Types

```sql
select
    relationship_type,
    relationship_direction
from {{ ref('nexus_relationships_metadata') }}
where entity_a_type = 'person'
  and entity_b_type = 'group'
order by relationship_type
```

### Analyze Relationship Directions

```sql
select
    relationship_type,
    relationship_direction,
    count(*) as count
from {{ ref('nexus_relationships_metadata') }}
group by relationship_type, relationship_direction
order by relationship_type, relationship_direction
```

## Usage

This metadata table is automatically maintained by the `nexus_relationships_metadata` model, which selects distinct combinations from `nexus_relationships`. The table is materialized as a table for fast querying.

## Related Tables

- [`nexus_relationships`](../identity-resolution/index.md) - The main relationships table
- [`nexus_events_metadata`](events.md) - Events metadata
- [`nexus_entity_traits_metadata`](entity_traits.md) - Entity traits metadata
- [`nexus_entity_identifiers_metadata`](entity_identifiers.md) - Entity identifiers metadata
