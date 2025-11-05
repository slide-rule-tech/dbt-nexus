---
title: Examples
tags: [mcp, examples, usage]
summary: Usage examples and query patterns for Nexus MCP tools
---

# Usage Examples

Common patterns and examples for using Nexus MCP tools with the unified entity architecture.

## Finding an Entity

### By Email (Person)
```json
{
  "tool": "nexus_get_entity_by_identifier",
  "arguments": {
    "identifier": "john.doe@example.com",
    "entity_type": "person"
  }
}
```

### By Entity ID
```json
{
  "tool": "nexus_get_entity_by_identifier",
  "arguments": {
    "identifier": "per_abc123"
  }
}
```

### By Domain (Group)
```json
{
  "tool": "nexus_get_entity_by_identifier",
  "arguments": {
    "identifier": "example.com",
    "entity_type": "group"
  }
}
```

## Getting Related Data

### Groups for a Person
```json
{
  "tool": "nexus_get_related_entities",
  "arguments": {
    "entity_id": "per_abc123",
    "relationship_type": "membership",
    "related_entity_type": "group",
    "limit": 10
  }
}
```

### Persons in a Group
```json
{
  "tool": "nexus_get_related_entities",
  "arguments": {
    "entity_id": "grp_xyz789",
    "relationship_type": "membership",
    "related_entity_type": "person",
    "orderBy": [
      {
        "column": "name",
        "direction": "ASC"
      }
    ]
  }
}
```

### Recent Events for an Entity
```json
{
  "tool": "nexus_get_recent_events_for_entity",
  "arguments": {
    "entity_id": "per_abc123",
    "entity_type": "person",
    "limit": 20,
    "filters": [
      {
        "column": "occurred_at",
        "operator": ">",
        "value": "2024-01-01T00:00:00Z"
      }
    ]
  }
}
```

### Trait History
```json
{
  "tool": "nexus_get_trait_history",
  "arguments": {
    "entity_id": "per_abc123",
    "trait_name": "name",
    "limit": 10
  }
}
```

### Edges for an Entity
```json
{
  "tool": "nexus_get_edges_for_entity",
  "arguments": {
    "entity_id": "per_abc123",
    "entity_type": "person",
    "limit": 20
  }
}
```

## Searching Events

### Text Search
```json
{
  "tool": "nexus_search_events",
  "arguments": {
    "query": "task completed",
    "limit": 50
  }
}
```

### With Filters
```json
{
  "tool": "nexus_search_events",
  "arguments": {
    "query": "task",
    "filters": [
      {
        "column": "type",
        "operator": "=",
        "value": "task_management"
      },
      {
        "column": "occurred_at",
        "operator": ">=",
        "value": "2024-01-01"
      }
    ],
    "orderBy": [
      {
        "column": "occurred_at",
        "direction": "DESC"
      }
    ],
    "limit": 25
  }
}
```

## Filtering Lists

### List Persons by Email Domain
```json
{
  "tool": "nexus_list_entities",
  "arguments": {
    "entity_type": "person",
    "filters": [
      {
        "column": "email",
        "operator": "LIKE",
        "value": "%@example.com"
      }
    ],
    "orderBy": [
      {
        "column": "name",
        "direction": "ASC"
      }
    ],
    "limit": 100
  }
}
```

### List Groups with Multiple Filters
```json
{
  "tool": "nexus_list_entities",
  "arguments": {
    "entity_type": "group",
    "filters": [
      {
        "column": "domain",
        "operator": "IS NOT NULL"
      },
      {
        "column": "company_name",
        "operator": "LIKE",
        "value": "%Tech%"
      }
    ],
    "limit": 50
  }
}
```

### List All Entities (No Type Filter)
```json
{
  "tool": "nexus_list_entities",
  "arguments": {
    "filters": [
      {
        "column": "entity_type",
        "operator": "IN",
        "value": ["person", "group"]
      }
    ],
    "limit": 100
  }
}
```

### List Memberships with Filtering
```json
{
  "tool": "nexus_list_memberships",
  "arguments": {
    "filters": [
      {
        "column": "entity_a_role",
        "operator": "=",
        "value": "primary_contact"
      }
    ],
    "orderBy": [
      {
        "column": "established_at",
        "direction": "DESC"
      }
    ]
  }
}
```

## Advanced Filtering

### Using IN Operator
```json
{
  "tool": "nexus_list_entities",
  "arguments": {
    "entity_type": "person",
    "filters": [
      {
        "column": "email",
        "operator": "IN",
        "value": ["user1@example.com", "user2@example.com"]
      }
    ]
  }
}
```

### Using IS NULL
```json
{
  "tool": "nexus_list_entities",
  "arguments": {
    "entity_type": "group",
    "filters": [
      {
        "column": "domain",
        "operator": "IS NOT NULL"
      }
    ]
  }
}
```

### Combining Multiple Filters
```json
{
  "tool": "nexus_search_events",
  "arguments": {
    "filters": [
      {
        "column": "source",
        "operator": "=",
        "value": "notion"
      },
      {
        "column": "type",
        "operator": "=",
        "value": "task_management"
      },
      {
        "column": "occurred_at",
        "operator": ">",
        "value": "2024-01-01"
      }
    ]
  }
}
```

### Filtering by Timestamp Fields

#### Events Recently Processed
```json
{
  "tool": "nexus_search_events",
  "arguments": {
    "filters": [
      {
        "column": "_processed_at",
        "operator": ">",
        "value": "2024-01-15T00:00:00Z"
      }
    ],
    "orderBy": [
      {
        "column": "_processed_at",
        "direction": "DESC"
      }
    ]
  }
}
```

#### Entities Recently Updated
```json
{
  "tool": "nexus_list_entities",
  "arguments": {
    "entity_type": "person",
    "filters": [
      {
        "column": "_updated_at",
        "operator": ">",
        "value": "2024-01-01T00:00:00Z"
      }
    ],
    "orderBy": [
      {
        "column": "_updated_at",
        "direction": "DESC"
      }
    ]
  }
}
```

#### Entities Created Recently
```json
{
  "tool": "nexus_list_entities",
  "arguments": {
    "entity_type": "person",
    "filters": [
      {
        "column": "_created_at",
        "operator": ">",
        "value": "2024-01-01T00:00:00Z"
      }
    ],
    "orderBy": [
      {
        "column": "_created_at",
        "direction": "DESC"
      }
    ]
  }
}
```

#### Entities with Recent Interactions
```json
{
  "tool": "nexus_list_entities",
  "arguments": {
    "entity_type": "person",
    "filters": [
      {
        "column": "last_interaction_at",
        "operator": ">",
        "value": "2024-01-01T00:00:00Z"
      }
    ],
    "orderBy": [
      {
        "column": "last_interaction_at",
        "direction": "DESC"
      }
    ]
  }
}
```

#### Relationships Recently Updated
```json
{
  "tool": "nexus_list_memberships",
  "arguments": {
    "filters": [
      {
        "column": "_updated_at",
        "operator": ">",
        "value": "2024-01-01T00:00:00Z"
      }
    ],
    "orderBy": [
      {
        "column": "_updated_at",
        "direction": "DESC"
      }
    ]
  }
}
```

## Pagination

### Paginated List
```json
{
  "tool": "nexus_list_entities",
  "arguments": {
    "entity_type": "person",
    "limit": 50,
    "offset": 100,
    "orderBy": [
      {
        "column": "email",
        "direction": "ASC"
      }
    ]
  }
}
```

## Getting Event Participants

### All Participants for an Event
```json
{
  "tool": "nexus_get_event_participants",
  "arguments": {
    "event_id": "evt_123456"
  }
}
```

### Filtered Participants
```json
{
  "tool": "nexus_get_event_participants",
  "arguments": {
    "event_id": "evt_123456",
    "filters": [
      {
        "column": "entity_type",
        "operator": "=",
        "value": "person"
      }
    ]
  }
}
```

## Common Query Patterns

### Complete Entity Profile
1. Get entity by identifier
2. Get related entities (e.g., groups for a person)
3. Get recent events for entity
4. Get trait history
5. Get edges for entity

### Relationship Analysis
1. Get entity by identifier
2. Get related entities with relationship filters
3. List memberships for analysis

### Event Investigation
1. Search for events
2. Get event details
3. Get event participants
4. Get entities for participants

### Trait Analysis
1. Get entity by identifier
2. Get trait history for specific traits
3. Analyze trait changes over time
