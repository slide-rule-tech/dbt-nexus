import type { DbtConfig, NexusModels } from "./types.js";
import { existsSync, readFileSync } from "fs";

import { join } from "path";

/**
 * Discover nexus models from manifest.json
 */
export function discoverNexusModels(config: DbtConfig): NexusModels {
  const manifestPath = join(config.projectDir, "target", "manifest.json");

  if (!existsSync(manifestPath)) {
    throw new Error(
      `manifest.json not found at ${manifestPath}. Please run 'dbt compile' or 'dbt run' first.`
    );
  }

  const manifest = JSON.parse(readFileSync(manifestPath, "utf-8"));

  // Find nexus models by name patterns
  const nodes = manifest.nodes || {};

  // Look for nexus models - they might be in different packages or the main project
  const findModel = (pattern: string): string | null => {
    // First try exact match
    for (const [nodeId, node] of Object.entries(nodes)) {
      const nodeData = node as any;
      if (nodeData.name === pattern || nodeId.endsWith(`.${pattern}`)) {
        return nodeData.relation_name || null;
      }
    }

    // Try partial match (case-insensitive)
    for (const [nodeId, node] of Object.entries(nodes)) {
      const nodeData = node as any;
      const name = (nodeData.name || "").toLowerCase();
      if (name.includes(pattern.toLowerCase())) {
        return nodeData.relation_name || null;
      }
    }

    return null;
  };

  // Find required nexus models
  const entities = findModel("nexus_entities");
  const relationships = findModel("nexus_relationships");
  const events = findModel("nexus_events");
  const entityParticipants = findModel("nexus_entity_participants");
  const entityTraits = findModel("nexus_entity_traits");
  const entityIdentifiers = findModel("nexus_entity_identifiers");
  const entityIdentifiersEdges = findModel("nexus_entity_identifiers_edges");
  const resolvedPersonIdentifiers = findModel(
    "nexus_resolved_person_identifiers"
  );
  const resolvedGroupIdentifiers = findModel(
    "nexus_resolved_group_identifiers"
  );

  console.error("🔍 Discovered models:", {
    entities: entities ? "✓" : "✗",
    relationships: relationships ? "✓" : "✗",
    events: events ? "✓" : "✗",
    entityParticipants: entityParticipants ? "✓" : "✗",
    entityTraits: entityTraits ? "✓" : "✗",
    entityIdentifiers: entityIdentifiers ? "✓" : "✗",
    entityIdentifiersEdges: entityIdentifiersEdges ? "✓" : "✗",
    resolvedPersonIdentifiers: resolvedPersonIdentifiers ? "✓" : "✗",
    resolvedGroupIdentifiers: resolvedGroupIdentifiers ? "✓" : "✗",
  });

  if (!entities || !relationships || !events || !entityParticipants) {
    throw new Error(
      `Required nexus models not found in manifest. Found: entities=${!!entities}, relationships=${!!relationships}, events=${!!events}, participants=${!!entityParticipants}`
    );
  }

  // Extract schema from the first model's relation_name
  // Format: "project.dataset.table" for BigQuery or "database.schema.table" for Snowflake
  const getSchema = (relationName: string): string => {
    const parts = relationName.split(".");
    if (parts.length >= 3) {
      // BigQuery: project.dataset.table
      // Snowflake: database.schema.table
      return parts.slice(0, -1).join(".");
    } else if (parts.length === 2) {
      // dataset.table format
      return parts[0];
    }
    return "default";
  };

  const schema = getSchema(entities!);

  // Use fallback if not found, but ensure we have valid relation names
  const resolvedPersons =
    resolvedPersonIdentifiers || findModel("resolved_person_identifiers");
  const resolvedGroups =
    resolvedGroupIdentifiers || findModel("resolved_group_identifiers");

  // Helper to create fallback relation name by replacing the table name part
  const createFallbackRelation = (
    baseRelation: string,
    newTableName: string
  ): string => {
    // baseRelation is like: `project`.`dataset`.`table_name`
    // We need to replace the last part (table_name) with newTableName
    const parts = baseRelation.split(".");
    if (parts.length >= 3) {
      // Replace the last part (remove backticks, replace name, add backticks)
      const lastPart = parts[parts.length - 1].replace(/`/g, "");
      parts[parts.length - 1] = `\`${newTableName}\``;
      return parts.join(".");
    }
    return baseRelation;
  };

  return {
    entities: entities!,
    relationships:
      relationships || createFallbackRelation(entities!, "nexus_relationships"),
    events: events!,
    entityParticipants: entityParticipants!,
    entityTraits: entityTraits || createFallbackRelation(entities!, "nexus_entity_traits"),
    entityIdentifiers: entityIdentifiers || createFallbackRelation(entities!, "nexus_entity_identifiers"),
    entityIdentifiersEdges: entityIdentifiersEdges || createFallbackRelation(entities!, "nexus_entity_identifiers_edges"),
    resolvedPersonIdentifiers:
      resolvedPersons ||
      createFallbackRelation(entities!, "nexus_resolved_person_identifiers"),
    resolvedGroupIdentifiers:
      resolvedGroups ||
      createFallbackRelation(entities!, "nexus_resolved_group_identifiers"),
    schema,
  };
}

/**
 * Get table name from relation name (remove schema prefix)
 */
export function getTableName(relationName: string): string {
  const parts = relationName.split(".");
  return parts[parts.length - 1];
}

/**
 * Get qualified table name for queries (with backticks for BigQuery)
 * relation_name from manifest includes backticks like: `project`.`dataset`.`table`
 * We need to parse it and rebuild it properly to avoid template literal issues
 */
export function getQualifiedTableName(
  relationName: string,
  adapterType: "bigquery" | "snowflake"
): string {
  if (!relationName) {
    throw new Error("relationName is empty or undefined");
  }

  // relation_name from dbt manifest is like: `project`.`dataset`.`table`
  // We need to parse it and rebuild it to ensure proper formatting
  // Remove backticks and split by `.`
  const cleaned = relationName.replace(/`/g, "").trim();
  const parts = cleaned.split(".").filter((p) => p.length > 0);

  if (parts.length === 0) {
    throw new Error(`Invalid relation_name format: ${relationName}`);
  }

  // Rebuild with proper backticks for BigQuery
  if (adapterType === "bigquery") {
    return parts.map((part) => `\`${part}\``).join(".");
  } else {
    // Snowflake will be transformed in warehouse client
    return parts.map((part) => `\`${part}\``).join(".");
  }
}
