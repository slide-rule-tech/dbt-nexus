---
title: Events Metadata
tags: [metadata, events, reference]
summary:
  Metadata table providing distinct event names, types, sources, and value units
  from nexus_events
---

The `nexus_events_metadata` table provides a catalog of all distinct event
configurations present in the `nexus_events` table. This metadata table is
useful for understanding what events are available in your data and how they're
structured across different sources.

## Overview

This metadata table aggregates distinct combinations of event attributes, making
it easy to:

- Discover available events across all sources
- Understand event naming conventions
- Identify event types and their associated sources
- Track value units used for events

## Schema

| Field        | Type   | Description                           |
| ------------ | ------ | ------------------------------------- |
| `event_name` | String | The specific event name               |
| `event_type` | String | The event category or type            |
| `source`     | String | The source system for the event       |
| `value_unit` | String | The unit of measurement for the value |

## Query Examples

### Discover All Available Events

```sql
select
    event_name,
    event_type,
    source,
    value_unit
from {{ ref('nexus_events_metadata') }}
order by source, event_type, event_name
```

### Find Events by Type

```sql
select
    event_name,
    source,
    value_unit
from {{ ref('nexus_events_metadata') }}
where event_type = 'appointment'
order by source, event_name
```

### Count Events by Source

```sql
select
    source,
    count(distinct event_name) as unique_events,
    count(distinct event_type) as unique_types
from {{ ref('nexus_events_metadata') }}
group by source
order by unique_events desc
```

### Find Events with Value Units

```sql
select
    event_name,
    event_type,
    source,
    value_unit
from {{ ref('nexus_events_metadata') }}
where value_unit is not null
order by source, event_name
```

## Usage

This metadata table is automatically maintained by the `nexus_events_metadata`
model, which selects distinct combinations from `nexus_events`. The table is
materialized as a table for fast querying.

## Related Tables

- [`nexus_events`](../event-log/event-schema-quick-reference.md) - The main
  events table
- [`nexus_entity_traits_metadata`](entity_traits.md) - Entity traits metadata
- [`nexus_entity_identifiers_metadata`](entity_identifiers.md) - Entity
  identifiers metadata
- [`nexus_relationships_metadata`](relationships.md) - Relationships metadata
