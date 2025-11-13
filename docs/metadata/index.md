---
title: Metadata Tables
tags: [metadata, reference, tables]
summary:
  Metadata tables providing catalogs of distinct configurations from nexus
  models
---

The nexus package includes metadata tables that provide catalogs of distinct
configurations from the main nexus models. These metadata tables are useful for
understanding what data is available in your nexus models and how it's
structured.

## Overview

Metadata tables are automatically maintained by dbt models that select distinct
combinations from the main nexus tables. These tables are materialized as tables
for fast querying and are updated whenever the main nexus models are run.

## Available Metadata Tables

### Events Metadata

The [`nexus_events_metadata`](tables/events.md) table provides a catalog of all
distinct event configurations, including:

- Event names
- Event types
- Sources
- Value units

**Use cases:**

- Discover available events across all sources
- Understand event naming conventions
- Identify event types and their associated sources
- Track value units used for events

### Entity Traits Metadata

The [`nexus_entity_traits_metadata`](tables/entity_traits.md) table provides a
catalog of all distinct entity trait configurations, including:

- Entity types
- Trait names

**Use cases:**

- Discover available traits for each entity type
- Understand trait naming conventions
- Identify which traits are available for persons vs groups
- Track trait coverage across entity types

### Entity Identifiers Metadata

The [`nexus_entity_identifiers_metadata`](tables/entity_identifiers.md) table
provides a catalog of all distinct entity identifier configurations, including:

- Entity types
- Identifier types

**Use cases:**

- Discover available identifier types for each entity type
- Understand identifier type naming conventions
- Identify which identifier types are available for persons vs groups
- Track identifier coverage across entity types

### Relationships Metadata

The [`nexus_relationships_metadata`](tables/relationships.md) table provides a
catalog of all distinct relationship configurations, including:

- Relationship types
- Entity types (A and B)
- Relationship directions

**Use cases:**

- Discover available relationship types
- Understand which entity types can have relationships
- Identify relationship directions (a_to_b, b_to_a, bidirectional)
- Track relationship patterns across your data

## Usage

All metadata tables are automatically maintained by dbt models in the
`metadata/` folder. These tables are materialized as tables for fast querying
and are updated whenever the main nexus models are run.

### Query Metadata Tables

```sql
-- Example: Discover all available events
select
    event_name,
    event_type,
    source,
    value_unit
from {{ ref('nexus_events_metadata') }}
order by source, event_type, event_name
```

### Count Distinct Configurations

```sql
-- Example: Count events by source
select
    source,
    count(distinct event_name) as unique_events,
    count(distinct event_type) as unique_types
from {{ ref('nexus_events_metadata') }}
group by source
order by unique_events desc
```

## Related Documentation

- [Event Log](../event-log/event-schema-quick-reference.md) - Event schema and
  requirements
- [Identity Resolution](../identity-resolution/index.md) - Entity traits,
  identifiers, and relationships
- [Database Schema](../overview/database-schema.md) - Complete database schema
  overview
