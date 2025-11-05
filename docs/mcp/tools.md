---
title: Tool Reference
tags: [mcp, tools, reference]
summary: Complete reference for all Nexus MCP tools
---

# Tool Reference

Complete documentation for all available Nexus MCP tools. All tools follow the
v2 unified entity architecture, supporting both person and group entities.

## Common Parameters

Many tools share common parameters:

### Filters

```typescript
{
  column: string;      // Column name to filter
  operator: "=" | "!=" | ">" | "<" | ">=" | "<=" | "LIKE" | "IN" | "IS NULL" | "IS NOT NULL";
  value?: any;         // Filter value (not required for IS NULL/IS NOT NULL)
}
```

### OrderBy

```typescript
{
  column: string; // Column name to sort by
  direction: "ASC" | "DESC";
}
```

## Entity Tools

### nexus_get_entity_by_identifier

Get an entity by identifier (email, entity_id, domain, etc.). Works for both
person and group entities.

**Parameters:**

- `identifier` (string, required): Entity identifier (email, entity_id, domain,
  etc.)
- `entity_type` (string, optional): Filter by entity type ("person" or "group")

**Returns:**

- Entity with `membership_count` (for persons) or `person_count` (for groups)

**Example:**

```json
{
  "identifier": "user@example.com",
  "entity_type": "person"
}
```

### nexus_list_entities

List entities with optional filtering. Works for both person and group entities.

**Parameters:**

- `entity_type` (string, optional): Filter by entity type ("person" or "group")
- `filters` (array, optional): Additional filters
- `orderBy` (array, optional): Sorting specification
- `limit` (number, optional): Maximum results
- `offset` (number, optional): Pagination offset

**Returns:**

- Array of entities with `membership_count` or `person_count` (when entity_type
  is specified and no filters)

**Example:**

```json
{
  "entity_type": "person",
  "filters": [
    {
      "column": "email",
      "operator": "LIKE",
      "value": "%@example.com"
    }
  ],
  "limit": 50
}
```

### nexus_get_recent_events_for_entity

Get recent events for an entity (person or group).

**Parameters:**

- `entity_id` (string, required): Entity ID
- `entity_type` (string, optional): Filter by entity type ("person" or "group")
- `filters` (array, optional): Additional filters
- `orderBy` (array, optional): Sorting (default: `occurred_at DESC`)
- `limit` (number, optional): Maximum results (default: 10)

**Returns:**

- Array of events with participant role information

**Example:**

```json
{
  "entity_id": "per_123",
  "entity_type": "person",
  "limit": 20
}
```

### nexus_get_related_entities

Get related entities for an entity. Returns entities connected through
relationships (e.g., groups for a person, persons for a group).

**Parameters:**

- `entity_id` (string, required): Entity ID
- `relationship_type` (string, optional): Filter by relationship type (e.g.,
  "membership")
- `related_entity_type` (string, optional): Filter by related entity type
  ("person" or "group")
- `filters` (array, optional): Additional filters
- `orderBy` (array, optional): Sorting (default: `established_at DESC`)
- `limit` (number, optional): Maximum results
- `offset` (number, optional): Pagination offset

**Returns:**

- Array of related entities with relationship details

**Example:**

```json
{
  "entity_id": "per_123",
  "relationship_type": "membership",
  "related_entity_type": "group",
  "limit": 10
}
```

### nexus_get_trait_history

Get trait history for an entity. Returns all historical values of a specific
trait for an entity, ordered by occurred_at descending.

**Parameters:**

- `entity_id` (string, required): Entity ID (person_id or group_id)
- `trait_name` (string, required): Trait name (e.g., "name", "email")
- `orderBy` (array, optional): Sorting specification
- `limit` (number, optional): Maximum results

**Returns:**

- Array of trait history records with associated event information

**Example:**

```json
{
  "entity_id": "per_123",
  "trait_name": "name",
  "limit": 10
}
```

### nexus_get_edges_for_entity

Get edges (connections between identifiers) for an entity. Returns all edges
where the entity's identifiers appear, with associated event information.

**Parameters:**

- `entity_id` (string, required): Entity ID
- `entity_type` (string, optional): Filter by entity type ("person" or "group")
- `orderBy` (array, optional): Sorting specification
- `limit` (number, optional): Maximum results

**Returns:**

- Array of edges with associated event information

**Example:**

```json
{
  "entity_id": "per_123",
  "entity_type": "person",
  "limit": 20
}
```

## Event Tools

### nexus_search_events

Search events with flexible text search and filtering.

**Parameters:**

- `query` (string, optional): Text search query (searches name, type, source)
- `filters` (array, optional): Additional filters
- `orderBy` (array, optional): Sorting (default: `occurred_at DESC`)
- `limit` (number, optional): Maximum results (default: 50)

**Returns:**

- Array of matching events

**Example:**

```json
{
  "query": "task",
  "filters": [
    {
      "column": "occurred_at",
      "operator": ">",
      "value": "2024-01-01"
    }
  ],
  "limit": 20
}
```

### nexus_get_event_participants

Get all participants (persons and groups) for an event.

**Parameters:**

- `event_id` (string, required): Event ID
- `filters` (array, optional): Additional filters

**Returns:**

- Array of participants with entity details and roles

**Example:**

```json
{
  "event_id": "evt_123",
  "filters": [
    {
      "column": "entity_type",
      "operator": "=",
      "value": "person"
    }
  ]
}
```

## Relationship Tools

### nexus_list_memberships

List all memberships (relationships) with optional filtering.

**Parameters:**

- `filters` (array, optional): Filters to apply
- `orderBy` (array, optional): Sorting (default: `established_at DESC`)
- `limit` (number, optional): Maximum results
- `offset` (number, optional): Pagination offset

**Returns:**

- Array of membership relationships

**Example:**

```json
{
  "filters": [
    {
      "column": "relationship_type",
      "operator": "=",
      "value": "membership"
    }
  ],
  "limit": 50
}
```

## Response Format

All tools return responses in this format:

```json
{
  "data": [...],           // Array of result rows
  "rowCount": 10,          // Number of rows returned
  "executionTime": 123,    // Query execution time in ms
  "query": "SELECT ..."    // Generated SQL query (for debugging)
}
```
