# Nexus MCP Server

An MCP (Model Context Protocol) server that connects to dbt-nexus projects and
exposes tools for querying entities (persons and groups), relationships, and
events from BigQuery or Snowflake data warehouses. Follows the v2 unified entity
architecture.

## Features

- **Auto-detection**: Automatically discovers dbt project and nexus models
- **Multi-warehouse support**: Works with BigQuery and Snowflake
- **Unified entity architecture**: Single tools for both person and group
  entities (v2 compatible)
- **Comprehensive tools**: 9 tools for querying nexus data
- **Flexible filtering**: Support for complex filters, sorting, and pagination
- **Query transparency**: Returns generated SQL for debugging

## Installation

```bash
cd dbt_packages/nexus/mcp-nexus
npm install
npm run build
```

## Quick Start

1. **Build the project**:

   ```bash
   npm run build
   ```

2. **Configure MCP in Cursor**: Add to `.cursor/mcp.json`:

   ```json
   {
     "mcpServers": {
       "nexus": {
         "command": "node",
         "args": [
           "/path/to/dbt_packages/nexus/mcp-nexus/dist/index.js",
           "--project-dir",
           "."
         ],
         "env": {
           "DBT_PROFILES_DIR": "~/.dbt"
         }
       }
     }
   }
   ```

3. **Ensure dbt models are built**:
   ```bash
   dbt compile  # or dbt run
   ```

## Available Tools

### Entity Tools (Unified - Works for both persons and groups)

- `nexus_get_entity_by_identifier` - Get entity by email, entity_id, domain,
  etc.
- `nexus_list_entities` - List entities with filtering (optional entity_type
  filter)
- `nexus_get_recent_events_for_entity` - Get recent events for an entity
- `nexus_get_related_entities` - Get related entities through relationships
- `nexus_get_trait_history` - Get trait history for an entity
- `nexus_get_edges_for_entity` - Get identifier edges for an entity

### Event Tools

- `nexus_search_events` - Search events with text search
- `nexus_get_event_participants` - Get all participants for an event

### Relationship Tools

- `nexus_list_memberships` - List all memberships (relationships)

## Usage Examples

### Get Entity by Identifier

```json
{
  "tool": "nexus_get_entity_by_identifier",
  "arguments": {
    "identifier": "user@example.com",
    "entity_type": "person"
  }
}
```

### List Entities

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
    "limit": 50
  }
}
```

### Get Related Entities

```json
{
  "tool": "nexus_get_related_entities",
  "arguments": {
    "entity_id": "per_123",
    "relationship_type": "membership",
    "related_entity_type": "group"
  }
}
```

### Search Events

```json
{
  "tool": "nexus_search_events",
  "arguments": {
    "query": "task",
    "limit": 20,
    "filters": [
      {
        "column": "occurred_at",
        "operator": ">",
        "value": "2024-01-01"
      }
    ]
  }
}
```

## Configuration

The server automatically:

- Finds `dbt_project.yml` in the working directory
- Loads profiles from `~/.dbt/profiles.yml` or `DBT_PROFILES_DIR`
- Reads `target/manifest.json` to discover nexus models
- Connects to the warehouse using dbt target credentials

## Development

```bash
# Install dependencies
npm install

# Build TypeScript
npm run build

# Run in development mode
npm run dev
```

## Documentation

See [docs/mcp/](../docs/mcp/) for complete documentation:

- [Installation Guide](../docs/mcp/installation.md)
- [Tool Reference](../docs/mcp/tools.md)
- [Examples](../docs/mcp/examples.md)
- [Troubleshooting](../docs/mcp/troubleshooting.md)
