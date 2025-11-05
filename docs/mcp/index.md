---
title: Nexus MCP Server
tags: [mcp, nexus, tools]
summary: Overview of the Nexus MCP server for querying dbt-nexus data
---

# Nexus MCP Server

The Nexus MCP (Model Context Protocol) server provides a standardized interface for querying dbt-nexus data from BigQuery or Snowflake data warehouses. It automatically discovers your dbt project configuration and nexus models, then exposes tools for querying entities (persons and groups), relationships, and events. Follows the v2 unified entity architecture.

## What is MCP?

Model Context Protocol (MCP) is a protocol that enables AI assistants and tools to securely access and interact with data sources. The Nexus MCP server implements this protocol to provide access to your dbt-nexus data warehouse.

## Features

- **Auto-discovery**: Automatically finds your dbt project and discovers nexus models
- **Multi-warehouse**: Supports both BigQuery and Snowflake
- **Flexible queries**: Advanced filtering, sorting, and pagination
- **Query transparency**: All queries return SQL for debugging
- **Performance optimized**: Includes aggregations when appropriate

## Architecture

The MCP server:

1. **Auto-detects** your dbt project by finding `dbt_project.yml`
2. **Loads** your dbt profile and target configuration
3. **Discovers** nexus models from `target/manifest.json`
4. **Connects** to your data warehouse (BigQuery or Snowflake)
5. **Exposes** tools for querying nexus data

## Available Tools

### Entity Tools (Unified - Works for both persons and groups)
- `nexus_get_entity_by_identifier` - Find entity by email, entity_id, domain, etc.
- `nexus_list_entities` - List entities with filtering (optional entity_type filter)
- `nexus_get_recent_events_for_entity` - Get recent events for an entity
- `nexus_get_related_entities` - Get related entities through relationships
- `nexus_get_trait_history` - Get trait history for an entity
- `nexus_get_edges_for_entity` - Get identifier edges for an entity

### Event Tools
- `nexus_search_events` - Search events with text search
- `nexus_get_event_participants` - Get all participants for an event

### Relationship Tools
- `nexus_list_memberships` - List all memberships (relationships)

## Quick Links

- [Installation Guide](installation.md) - Set up the MCP server
- [Tool Reference](tools.md) - Complete tool documentation
- [Examples](examples.md) - Usage examples and patterns
- [Troubleshooting](troubleshooting.md) - Common issues and solutions

