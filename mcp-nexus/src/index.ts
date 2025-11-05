#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { loadDbtConfig } from "./dbt.js";
import { createWarehouseClient } from "./warehouse.js";
import { discoverNexusModels } from "./models.js";
import * as tools from "./tools.js";
import type { Filter, OrderBy, ToolContext } from "./types.js";

// Global context (initialized on startup)
let toolContext: ToolContext | null = null;

/**
 * Initialize the MCP server
 */
async function initialize() {
  console.error("🚀 Initializing Nexus MCP Server...");

  // Parse command line arguments
  const args = process.argv.slice(2);
  let projectDir: string | undefined;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--project-dir" && i + 1 < args.length) {
      projectDir = args[i + 1];
      break;
    }
  }

  try {
    // Load dbt configuration
    console.error("📁 Loading dbt configuration...");
    const config = loadDbtConfig(projectDir);
    console.error(`✅ Found dbt project: ${config.project.name}`);

    // Create warehouse client
    console.error("🔌 Connecting to data warehouse...");
    const client = createWarehouseClient(config.target);
    console.error(`✅ Connected to ${config.target.type}`);

    // Discover nexus models
    console.error("🔍 Discovering nexus models...");
    const models = discoverNexusModels(config);
    console.error("✅ Discovered nexus models:", {
      entities: models.entities,
      relationships: models.relationships,
      events: models.events,
    });

    toolContext = {
      client,
      models,
    };

    console.error("✅ Nexus MCP Server initialized successfully");
  } catch (error: any) {
    console.error("❌ Failed to initialize:", error.message);
    throw error;
  }
}

/**
 * Create and configure MCP server
 */
async function createServer() {
  const server = new Server(
    {
      name: "nexus",
      version: "0.1.0",
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  // List available tools
  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
      {
        name: "nexus_get_entity_by_identifier",
        description:
          "Get an entity by identifier (email, entity_id, domain, etc.). Tries direct entity_id lookup first, then falls back to identifier lookup. Works for both person and group entities. Returns entity with membership_count or person_count.",
        inputSchema: {
          type: "object",
          properties: {
            identifier: {
              type: "string",
              description: "Entity identifier (email, entity_id, domain, etc.)",
            },
            entity_type: {
              type: "string",
              enum: ["person", "group"],
              description: "Optional entity type filter to narrow search",
            },
          },
          required: ["identifier"],
        },
      },
      {
        name: "nexus_get_related_entities",
        description:
          "Get related entities for an entity. Returns entities connected through relationships (e.g., groups for a person, persons for a group).",
        inputSchema: {
          type: "object",
          properties: {
            entity_id: { type: "string", description: "Entity ID" },
            relationship_type: {
              type: "string",
              description: "Optional relationship type filter (e.g., 'membership')",
            },
            related_entity_type: {
              type: "string",
              enum: ["person", "group"],
              description: "Optional related entity type filter",
            },
            filters: { type: "array" },
            orderBy: { type: "array" },
            limit: { type: "number" },
            offset: { type: "number" },
          },
          required: ["entity_id"],
        },
      },
      {
        name: "nexus_get_recent_events_for_entity",
        description:
          "Get recent events for an entity (person or group). Returns events with participant role information.",
        inputSchema: {
          type: "object",
          properties: {
            entity_id: { type: "string", description: "Entity ID" },
            entity_type: {
              type: "string",
              enum: ["person", "group"],
              description: "Optional entity type filter",
            },
            filters: {
              type: "array",
              description: "Optional filters",
              items: {
                type: "object",
                properties: {
                  column: { type: "string" },
                  operator: {
                    type: "string",
                    enum: [
                      "=",
                      "!=",
                      ">",
                      "<",
                      ">=",
                      "<=",
                      "LIKE",
                      "IN",
                      "IS NULL",
                      "IS NOT NULL",
                    ],
                  },
                  value: { type: ["string", "number", "array"] },
                },
              },
            },
            orderBy: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  column: { type: "string" },
                  direction: { type: "string", enum: ["ASC", "DESC"] },
                },
              },
            },
            limit: { type: "number", default: 10 },
          },
          required: ["entity_id"],
        },
      },
      {
        name: "nexus_search_events",
        description:
          "Search events with flexible filtering. Supports text search across name, type, and source fields.",
        inputSchema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Text search query (searches name, type, source)",
            },
            filters: {
              type: "array",
              description: "Optional filters",
              items: {
                type: "object",
                properties: {
                  column: { type: "string" },
                  operator: {
                    type: "string",
                    enum: [
                      "=",
                      "!=",
                      ">",
                      "<",
                      ">=",
                      "<=",
                      "LIKE",
                      "IN",
                      "IS NULL",
                      "IS NOT NULL",
                    ],
                  },
                  value: { type: ["string", "number", "array"] },
                },
              },
            },
            orderBy: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  column: { type: "string" },
                  direction: { type: "string", enum: ["ASC", "DESC"] },
                },
              },
            },
            limit: { type: "number", default: 50 },
          },
        },
      },
      {
        name: "nexus_get_event_participants",
        description:
          "Get all participants (persons and groups) for an event, including their roles.",
        inputSchema: {
          type: "object",
          properties: {
            event_id: { type: "string", description: "Event ID" },
            filters: { type: "array" },
          },
          required: ["event_id"],
        },
      },
      {
        name: "nexus_list_entities",
        description:
          "List entities with optional filtering, sorting, and pagination. Works for both person and group entities. Includes membership_count or person_count when entity_type is specified and no filters applied.",
        inputSchema: {
          type: "object",
          properties: {
            entity_type: {
              type: "string",
              enum: ["person", "group"],
              description: "Optional entity type filter",
            },
            filters: { type: "array" },
            orderBy: { type: "array" },
            limit: { type: "number" },
            offset: { type: "number" },
          },
        },
      },
      {
        name: "nexus_list_memberships",
        description:
          "List all memberships with optional filtering, sorting, and pagination.",
        inputSchema: {
          type: "object",
          properties: {
            filters: { type: "array" },
            orderBy: { type: "array" },
            limit: { type: "number" },
            offset: { type: "number" },
          },
        },
      },
      {
        name: "nexus_get_trait_history",
        description:
          "Get trait history for an entity. Returns all historical values of a specific trait for an entity, ordered by occurred_at descending.",
        inputSchema: {
          type: "object",
          properties: {
            entity_id: { type: "string", description: "Entity ID (person_id or group_id)" },
            trait_name: { type: "string", description: "Trait name (e.g., 'name', 'email')" },
            orderBy: { type: "array" },
            limit: { type: "number" },
          },
          required: ["entity_id", "trait_name"],
        },
      },
      {
        name: "nexus_get_edges_for_entity",
        description:
          "Get edges (connections between identifiers) for an entity (person or group). Returns all edges where the entity's identifiers appear, with associated event information.",
        inputSchema: {
          type: "object",
          properties: {
            entity_id: { type: "string", description: "Entity ID" },
            entity_type: {
              type: "string",
              enum: ["person", "group"],
              description: "Optional entity type filter",
            },
            orderBy: { type: "array" },
            limit: { type: "number" },
          },
          required: ["entity_id"],
        },
      },
    ],
  }));

  // Handle tool calls
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    if (!toolContext) {
      throw new Error("Server not initialized. Please wait for initialization to complete.");
    }

    const { name, arguments: args } = request.params;

    if (!args) {
      throw new Error("Tool arguments are required");
    }

    try {
      let result;

      switch (name) {
        case "nexus_get_entity_by_identifier":
          result = await tools.getEntityByIdentifier(
            toolContext,
            args.identifier as string,
            args.entity_type as "person" | "group" | undefined
          );
          break;

        case "nexus_get_related_entities":
          result = await tools.getRelatedEntities(
            toolContext,
            args.entity_id as string,
            args.relationship_type as string | undefined,
            args.related_entity_type as "person" | "group" | undefined,
            args.filters as Filter[] | undefined,
            args.orderBy as OrderBy[] | undefined,
            args.limit as number | undefined,
            args.offset as number | undefined
          );
          break;

        case "nexus_get_recent_events_for_entity":
          result = await tools.getRecentEventsForEntity(
            toolContext,
            args.entity_id as string,
            args.entity_type as "person" | "group" | undefined,
            args.filters as Filter[] | undefined,
            args.orderBy as OrderBy[] | undefined,
            (args.limit as number) || 10
          );
          break;

        case "nexus_search_events":
          result = await tools.searchEvents(
            toolContext,
            args.query as string | undefined,
            args.filters as Filter[] | undefined,
            args.orderBy as OrderBy[] | undefined,
            (args.limit as number) || 50
          );
          break;

        case "nexus_get_event_participants":
          result = await tools.getEventParticipants(
            toolContext,
            args.event_id as string,
            args.filters as Filter[] | undefined
          );
          break;

        case "nexus_list_entities":
          result = await tools.listEntities(
            toolContext,
            args.entity_type as "person" | "group" | undefined,
            args.filters as Filter[] | undefined,
            args.orderBy as OrderBy[] | undefined,
            args.limit as number | undefined,
            args.offset as number | undefined
          );
          break;

        case "nexus_list_memberships":
          result = await tools.listMemberships(
            toolContext,
            args.filters as Filter[] | undefined,
            args.orderBy as OrderBy[] | undefined,
            args.limit as number | undefined,
            args.offset as number | undefined
          );
          break;

        case "nexus_get_trait_history":
          result = await tools.getTraitHistory(
            toolContext,
            args.entity_id as string,
            args.trait_name as string,
            args.orderBy as OrderBy[] | undefined,
            args.limit as number | undefined
          );
          break;

        case "nexus_get_edges_for_entity":
          result = await tools.getEdgesForEntity(
            toolContext,
            args.entity_id as string,
            args.entity_type as "person" | "group" | undefined,
            args.orderBy as OrderBy[] | undefined,
            args.limit as number | undefined
          );
          break;

        default:
          throw new Error(`Unknown tool: ${name}`);
      }

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                data: result.data,
                rowCount: result.rowCount,
                executionTime: result.executionTime,
                query: result.query,
              },
              null,
              2
            ),
          },
        ],
      };
    } catch (error: any) {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                error: error.message,
                stack: error.stack,
              },
              null,
              2
            ),
          },
        ],
        isError: true,
      };
    }
  });

  return server;
}

/**
 * Main entry point
 */
async function main() {
  // Initialize server
  await initialize();

  // Create MCP server
  const server = await createServer();

  // Start server with stdio transport
  const transport = new StdioServerTransport();
  await server.connect(transport);

  console.error("✅ Nexus MCP Server ready");
}

// Always run when executed as script
main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});

