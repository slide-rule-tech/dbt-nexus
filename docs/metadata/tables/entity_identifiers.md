---
title: Entity Identifiers Metadata
tags: [metadata, entities, identifiers, reference]
summary:
  Metadata table providing distinct entity types and identifier types from
  nexus_entity_identifiers
---

The `nexus_entity_identifiers_metadata` table provides a catalog of all distinct
entity identifier configurations present in the `nexus_entity_identifiers`
table. This metadata table helps you understand what identifier types are
available for each entity type.

## Overview

This metadata table aggregates distinct combinations of entity types and
identifier types, making it easy to:

- Discover available identifier types for each entity type
- Understand identifier type naming conventions
- Identify which identifier types are available for persons vs groups
- Track identifier coverage across entity types

## Schema

| Field             | Type   | Description                                 |
| ----------------- | ------ | ------------------------------------------- |
| `entity_type`     | String | The entity type (person or group)           |
| `identifier_type` | String | The type of identifier (email, phone, etc.) |

## Query Examples

### Discover All Available Identifier Types

```sql
select
    entity_type,
    identifier_type
from {{ ref('nexus_entity_identifiers_metadata') }}
order by entity_type, identifier_type
```

### Find Identifier Types for a Specific Entity Type

```sql
select
    identifier_type
from {{ ref('nexus_entity_identifiers_metadata') }}
where entity_type = 'person'
order by identifier_type
```

### Count Identifier Types by Entity Type

```sql
select
    entity_type,
    count(distinct identifier_type) as unique_identifier_types
from {{ ref('nexus_entity_identifiers_metadata') }}
group by entity_type
order by entity_type
```

### Find Common Identifier Types Across Entity Types

```sql
select
    identifier_type,
    count(distinct entity_type) as entity_type_count,
    array_agg(distinct entity_type) as entity_types
from {{ ref('nexus_entity_identifiers_metadata') }}
group by identifier_type
having count(distinct entity_type) > 1
order by identifier_type
```

## Usage

This metadata table is automatically maintained by the
`nexus_entity_identifiers_metadata` model, which selects distinct combinations
from `nexus_entity_identifiers`. The table is materialized as a table for fast
querying.

## Related Tables

- [`nexus_entity_identifiers`](../identity-resolution/index.md) - The main
  entity identifiers table
- [`nexus_events_metadata`](events.md) - Events metadata
- [`nexus_entity_traits_metadata`](entity_traits.md) - Entity traits metadata
- [`nexus_relationships_metadata`](relationships.md) - Relationships metadata
