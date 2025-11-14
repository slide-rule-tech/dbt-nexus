---
title: Entity Traits Metadata
tags: [metadata, entities, traits, reference]
summary:
  Metadata table providing distinct entity types, trait names, and column types
  from nexus_entity_traits merged with nexus_entities
---

The `nexus_entity_traits_metadata` table provides a catalog of all distinct
entity trait configurations present in the `nexus_entity_traits` table, merged
with column type information from the `nexus_entities` table. This metadata
table helps you understand what traits are available for each entity type and
their corresponding data types in the entities table.

## Overview

This metadata table aggregates distinct combinations of entity types and trait
names, and merges them with column type information from `nexus_entities`,
making it easy to:

- Discover available traits for each entity type
- Understand trait naming conventions
- Identify which traits are available for persons vs groups
- Track trait coverage across entity types
- Know the data types of trait columns in `nexus_entities`

## Schema

| Field         | Type   | Description                                                      |
| ------------- | ------ | ---------------------------------------------------------------- |
| `entity_type` | String | The entity type (person or group)                                |
| `trait_name`  | String | The name of the trait                                            |
| `column_type` | String | The data type of the corresponding column in `nexus_entities` (if exists) |

## Query Examples

### Discover All Available Traits

```sql
select
    entity_type,
    trait_name,
    column_type
from {{ ref('nexus_entity_traits_metadata') }}
order by entity_type, trait_name
```

### Find Traits for a Specific Entity Type

```sql
select
    trait_name
from {{ ref('nexus_entity_traits_metadata') }}
where entity_type = 'person'
order by trait_name
```

### Count Traits by Entity Type

```sql
select
    entity_type,
    count(distinct trait_name) as unique_traits
from {{ ref('nexus_entity_traits_metadata') }}
group by entity_type
order by entity_type
```

### Find Common Traits Across Entity Types

```sql
select
    trait_name,
    count(distinct entity_type) as entity_type_count,
    array_agg(distinct entity_type) as entity_types
from {{ ref('nexus_entity_traits_metadata') }}
group by trait_name
having count(distinct entity_type) > 1
order by trait_name
```

### Find Traits with Column Types

```sql
select
    entity_type,
    trait_name,
    column_type
from {{ ref('nexus_entity_traits_metadata') }}
where column_type is not null
order by entity_type, trait_name
```

### Find Traits Without Corresponding Columns

```sql
select
    entity_type,
    trait_name
from {{ ref('nexus_entity_traits_metadata') }}
where column_type is null
order by entity_type, trait_name
```

### Group Traits by Column Type

```sql
select
    column_type,
    count(distinct trait_name) as trait_count,
    array_agg(distinct trait_name) as trait_names
from {{ ref('nexus_entity_traits_metadata') }}
where column_type is not null
group by column_type
order by trait_count desc
```

## Usage

This metadata table is automatically maintained by the
`nexus_entity_traits_metadata` model, which:

1. Selects distinct combinations from `nexus_entity_traits`
2. Queries column information from `nexus_entities` using
   `adapter.get_columns_in_relation()`
3. Matches trait names to their corresponding column names in `nexus_entities`
4. Merges the trait metadata with column type information

The table is materialized as a table for fast querying. The `column_type` field
will be `NULL` for traits that don't have a corresponding column in
`nexus_entities`.

## Related Tables

- [`nexus_entity_traits`](../identity-resolution/index.md) - The main entity
  traits table
- [`nexus_entities`](../identity-resolution/index.md) - The final entities table
  with pivoted trait columns
- [`nexus_events_metadata`](events.md) - Events metadata
- [`nexus_entity_identifiers_metadata`](entity_identifiers.md) - Entity
  identifiers metadata
- [`nexus_relationships_metadata`](relationships.md) - Relationships metadata
