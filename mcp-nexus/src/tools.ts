import type {
  Filter,
  NexusModels,
  OrderBy,
  QueryResult,
  ToolContext,
  WarehouseClient,
} from "./types.js";
import { buildDynamicSQL, buildWhereCondition } from "./sql-builder.js";

import { getQualifiedTableName } from "./models.js";

/**
 * Get entity by identifier (email, entity_id, domain, etc.)
 * Tries direct entity_id lookup first, then falls back to identifier lookup
 * Works for both person and group entities
 */
export async function getEntityByIdentifier(
  context: ToolContext,
  identifier: string,
  entityType?: "person" | "group"
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();
  const startTime = Date.now();

  const entitiesTable = getQualifiedTableName(models.entities, adapterType);

  // Build entity type filter
  const entityTypeFilter = entityType
    ? `AND p.entity_type = '${entityType}'`
    : "";

  // First try direct entity_id lookup with relationship counts
  let sql = `
    SELECT 
      p.*,
      COALESCE(m.membership_count, 0) as membership_count,
      COALESCE(g.person_count, 0) as person_count
    FROM ${entitiesTable} p
    LEFT JOIN (
      SELECT 
        entity_a_id as entity_id,
        COUNT(*) as membership_count
      FROM ${getQualifiedTableName(models.relationships, adapterType)}
      WHERE relationship_type = 'membership'
      GROUP BY entity_a_id
    ) m ON p.entity_id = m.entity_id
    LEFT JOIN (
      SELECT 
        entity_b_id as entity_id,
        COUNT(*) as person_count
      FROM ${getQualifiedTableName(models.relationships, adapterType)}
      WHERE relationship_type = 'membership'
      GROUP BY entity_b_id
    ) g ON p.entity_id = g.entity_id
    WHERE p.entity_id = '${escapeSQLString(identifier)}'
    ${entityTypeFilter}
    LIMIT 1
  `;

  console.error(
    "📝 Trying direct entity_id lookup:",
    sql.substring(0, 200) + "..."
  );

  let result = await client.executeQuery(sql);

  // If found by entity_id, return it
  if (result.data.length > 0) {
    console.error("✅ Found entity by direct entity_id");
    return result;
  }

  // If not found, try identifier lookup
  const personIdentifiersTable = getQualifiedTableName(
    models.resolvedPersonIdentifiers,
    adapterType
  );
  const groupIdentifiersTable = getQualifiedTableName(
    models.resolvedGroupIdentifiers,
    adapterType
  );

  // Try person identifiers if entity_type is person or not specified
  if (!entityType || entityType === "person") {
    sql = `
      SELECT 
        p.*,
        COALESCE(m.membership_count, 0) as membership_count,
        0 as person_count
      FROM ${entitiesTable} p
      JOIN ${personIdentifiersTable} pi ON p.entity_id = pi.person_id
      LEFT JOIN (
        SELECT 
          entity_a_id as entity_id,
          COUNT(*) as membership_count
        FROM ${getQualifiedTableName(models.relationships, adapterType)}
        WHERE relationship_type = 'membership'
        GROUP BY entity_a_id
      ) m ON p.entity_id = m.entity_id
      WHERE pi.identifier_value = '${escapeSQLString(identifier)}'
        AND p.entity_type = 'person'
      LIMIT 1
    `;

    console.error(
      "📝 Trying person_identifiers lookup:",
      sql.substring(0, 200) + "..."
    );

    result = await client.executeQuery(sql);

    if (result.data.length > 0) {
      console.error("✅ Found entity via person_identifiers table");
      return result;
    }
  }

  // Try group identifiers if entity_type is group or not specified
  if (!entityType || entityType === "group") {
    sql = `
      SELECT 
        p.*,
        0 as membership_count,
        COALESCE(g.person_count, 0) as person_count
      FROM ${entitiesTable} p
      JOIN ${groupIdentifiersTable} gi ON p.entity_id = gi.group_id
      LEFT JOIN (
        SELECT 
          entity_b_id as entity_id,
          COUNT(*) as person_count
        FROM ${getQualifiedTableName(models.relationships, adapterType)}
        WHERE relationship_type = 'membership'
        GROUP BY entity_b_id
      ) g ON p.entity_id = g.entity_id
      WHERE gi.identifier_value = '${escapeSQLString(identifier)}'
        AND p.entity_type = 'group'
      LIMIT 1
    `;

    console.error(
      "📝 Trying group_identifiers lookup:",
      sql.substring(0, 200) + "..."
    );

    result = await client.executeQuery(sql);

    if (result.data.length > 0) {
      console.error("✅ Found entity via group_identifiers table");
      return result;
    }
  }

  console.error("❌ Entity not found with identifier:", identifier);
  return result;
}

/**
 * Get related entities for an entity
 * Returns entities connected through relationships (e.g., groups for a person, persons for a group)
 */
export async function getRelatedEntities(
  context: ToolContext,
  entityId: string,
  relationshipType?: string,
  relatedEntityType?: "person" | "group",
  filters?: Filter[],
  orderBy?: OrderBy[],
  limit?: number,
  offset?: number
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();

  const relationshipsTable = getQualifiedTableName(
    models.relationships,
    adapterType
  );
  const entitiesTable = getQualifiedTableName(models.entities, adapterType);

  // Determine which side of the relationship to join based on entity type
  // We need to check the entity type first, but for now we'll try both sides
  let sql = `
    SELECT 
      r.*,
      e.*
    FROM ${relationshipsTable} r
    JOIN ${entitiesTable} e ON (
      (r.entity_a_id = '${escapeSQLString(
        entityId
      )}' AND e.entity_id = r.entity_b_id)
      OR
      (r.entity_b_id = '${escapeSQLString(
        entityId
      )}' AND e.entity_id = r.entity_a_id)
    )
    WHERE (r.entity_a_id = '${escapeSQLString(
      entityId
    )}' OR r.entity_b_id = '${escapeSQLString(entityId)}')
  `;

  // Add relationship type filter
  if (relationshipType) {
    sql += ` AND r.relationship_type = '${escapeSQLString(relationshipType)}'`;
  }

  // Add related entity type filter
  if (relatedEntityType) {
    sql += ` AND e.entity_type = '${relatedEntityType}'`;
  }

  // Add additional filters
  if (filters && filters.length > 0) {
    const conditions = filters.map((filter) => buildWhereCondition(filter));
    sql += ` AND ${conditions.join(" AND ")}`;
  }

  // Add ORDER BY
  if (orderBy && orderBy.length > 0) {
    const clauses = orderBy.map(
      (order) => `${order.column} ${order.direction}`
    );
    sql += ` ORDER BY ${clauses.join(", ")}`;
  } else {
    sql += ` ORDER BY r.established_at DESC`;
  }

  // Add LIMIT and OFFSET
  if (limit !== undefined) {
    sql += ` LIMIT ${limit}`;
  }
  if (offset !== undefined && offset > 0) {
    sql += ` OFFSET ${offset}`;
  }

  return await client.executeQuery(sql);
}

/**
 * Get recent events for an entity (person or group)
 */
export async function getRecentEventsForEntity(
  context: ToolContext,
  entityId: string,
  entityType?: "person" | "group",
  filters?: Filter[],
  orderBy?: OrderBy[],
  limit: number = 10
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();

  const eventsTable = getQualifiedTableName(models.events, adapterType);
  const participantsTable = getQualifiedTableName(
    models.entityParticipants,
    adapterType
  );

  // Validate tables are not empty
  if (!eventsTable || !participantsTable) {
    throw new Error(
      `Missing table names: events=${eventsTable}, participants=${participantsTable}`
    );
  }

  // Build entity type filter
  const entityTypeFilter = entityType
    ? `AND pp.entity_type = '${entityType}'`
    : "";

  console.error("🔍 Table names:", { eventsTable, participantsTable });

  let sql = `
    SELECT 
      e.*,
      pp.*
    FROM ${eventsTable} e
    JOIN ${participantsTable} pp ON e.event_id = pp.event_id
    WHERE pp.entity_id = '${escapeSQLString(entityId)}'
    ${entityTypeFilter}
  `;

  console.error("📝 Generated SQL:", sql);

  // Add additional filters
  if (filters && filters.length > 0) {
    const conditions = filters.map((filter) => buildWhereCondition(filter));
    sql += ` AND ${conditions.join(" AND ")}`;
  }

  // Add ORDER BY
  if (orderBy && orderBy.length > 0) {
    const clauses = orderBy.map(
      (order) => `${order.column} ${order.direction}`
    );
    sql += ` ORDER BY ${clauses.join(", ")}`;
  } else {
    sql += ` ORDER BY e.occurred_at DESC`;
  }

  // Add LIMIT
  sql += ` LIMIT ${limit}`;

  return await client.executeQuery(sql);
}

/**
 * Search events with flexible filtering
 */
export async function searchEvents(
  context: ToolContext,
  query?: string,
  filters?: Filter[],
  orderBy?: OrderBy[],
  limit: number = 50
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();

  const eventsTable = getQualifiedTableName(models.events, adapterType);

  const allFilters: Filter[] = [];

  // Add text search filters if query provided
  if (query) {
    allFilters.push(
      {
        column: "name",
        operator: "LIKE",
        value: `%${query}%`,
      },
      {
        column: "type",
        operator: "LIKE",
        value: `%${query}%`,
      },
      {
        column: "source",
        operator: "LIKE",
        value: `%${query}%`,
      }
    );
  }

  // Add additional filters
  if (filters) {
    allFilters.push(...filters);
  }

  // Build SQL with OR for text search, AND for other filters
  let sql = `SELECT * FROM ${eventsTable}`;

  if (allFilters.length > 0) {
    const conditions: string[] = [];

    if (query) {
      // Text search uses OR
      const textConditions = [
        `name LIKE '%${escapeSQLString(query)}%'`,
        `type LIKE '%${escapeSQLString(query)}%'`,
        `source LIKE '%${escapeSQLString(query)}%'`,
      ];
      conditions.push(`(${textConditions.join(" OR ")})`);
    }

    // Other filters use AND
    if (filters && filters.length > 0) {
      const filterConditions = filters.map((filter) =>
        buildWhereCondition(filter)
      );
      conditions.push(...filterConditions);
    }

    if (conditions.length > 0) {
      sql += ` WHERE ${conditions.join(" AND ")}`;
    }
  }

  // Add ORDER BY
  if (orderBy && orderBy.length > 0) {
    const clauses = orderBy.map(
      (order) => `${order.column} ${order.direction}`
    );
    sql += ` ORDER BY ${clauses.join(", ")}`;
  } else {
    sql += ` ORDER BY occurred_at DESC`;
  }

  // Add LIMIT
  sql += ` LIMIT ${limit}`;

  return await client.executeQuery(sql);
}

// Old functions removed - use unified entity functions instead:
// - getGroupByIdentifier -> getEntityByIdentifier(identifier, 'group')
// - getPersonsForGroup -> getRelatedEntities(groupId, 'membership', 'person')
// - getRecentEventsForGroup -> getRecentEventsForEntity(groupId, 'group')

/**
 * Get event participants (both persons and groups)
 */
export async function getEventParticipants(
  context: ToolContext,
  eventId: string,
  filters?: Filter[]
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();

  const participantsTable = getQualifiedTableName(
    models.entityParticipants,
    adapterType
  );
  const entitiesTable = getQualifiedTableName(models.entities, adapterType);

  let sql = `
    SELECT 
      pp.*,
      e.*
    FROM ${participantsTable} pp
    JOIN ${entitiesTable} e ON pp.entity_id = e.entity_id
    WHERE pp.event_id = '${escapeSQLString(eventId)}'
  `;

  if (filters && filters.length > 0) {
    const conditions = filters.map((filter) => buildWhereCondition(filter));
    sql += ` AND ${conditions.join(" AND ")}`;
  }

  sql += ` ORDER BY pp.entity_type, e.name`;

  return await client.executeQuery(sql);
}

/**
 * List entities with optional filtering
 * Works for both person and group entities
 */
export async function listEntities(
  context: ToolContext,
  entityType?: "person" | "group",
  filters?: Filter[],
  orderBy?: OrderBy[],
  limit?: number,
  offset?: number
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();

  const entitiesTable = getQualifiedTableName(models.entities, adapterType);

  // Build base filters
  const baseFilters: Filter[] = [];
  if (entityType) {
    baseFilters.push({
      column: "entity_type",
      operator: "=",
      value: entityType,
    });
  }
  if (filters) {
    baseFilters.push(...filters);
  }

  // Include relationship counts if no filters (for performance)
  const includeCounts = (!filters || filters.length === 0) && entityType;

  let sql = "";

  if (includeCounts && entityType === "person") {
    sql = `
      SELECT 
        p.*,
        COALESCE(m.membership_count, 0) as membership_count,
        0 as person_count
      FROM ${entitiesTable} p
      LEFT JOIN (
        SELECT 
          entity_a_id as entity_id,
          COUNT(*) as membership_count
        FROM ${getQualifiedTableName(models.relationships, adapterType)}
        WHERE relationship_type = 'membership'
        GROUP BY entity_a_id
      ) m ON p.entity_id = m.entity_id
      WHERE p.entity_type = 'person'
    `;

    if (filters && filters.length > 0) {
      const conditions = filters.map((filter) => buildWhereCondition(filter));
      sql += ` AND ${conditions.join(" AND ")}`;
    }

    if (orderBy && orderBy.length > 0) {
      const clauses = orderBy.map(
        (order) => `${order.column} ${order.direction}`
      );
      sql += ` ORDER BY ${clauses.join(", ")}`;
    } else {
      sql += ` ORDER BY p.email ASC`;
    }
  } else if (includeCounts && entityType === "group") {
    sql = `
      SELECT 
        g.*,
        0 as membership_count,
        COALESCE(m.person_count, 0) as person_count
      FROM ${entitiesTable} g
      LEFT JOIN (
        SELECT 
          entity_b_id as entity_id,
          COUNT(*) as person_count
        FROM ${getQualifiedTableName(models.relationships, adapterType)}
        WHERE relationship_type = 'membership'
        GROUP BY entity_b_id
      ) m ON g.entity_id = m.entity_id
      WHERE g.entity_type = 'group'
    `;

    if (filters && filters.length > 0) {
      const conditions = filters.map((filter) => buildWhereCondition(filter));
      sql += ` AND ${conditions.join(" AND ")}`;
    }

    if (orderBy && orderBy.length > 0) {
      const clauses = orderBy.map(
        (order) => `${order.column} ${order.direction}`
      );
      sql += ` ORDER BY ${clauses.join(", ")}`;
    } else {
      sql += ` ORDER BY g.domain ASC`;
    }
  } else {
    // Use dynamic SQL builder for filtered queries or when entity_type is not specified
    sql = buildDynamicSQL({
      table: entitiesTable,
      filters: baseFilters.length > 0 ? baseFilters : undefined,
      orderBy,
      limit,
      offset,
    });
  }

  // Add LIMIT and OFFSET if not already included by buildDynamicSQL
  if (includeCounts) {
    if (limit !== undefined) {
      sql += ` LIMIT ${limit}`;
    }
    if (offset !== undefined && offset > 0) {
      sql += ` OFFSET ${offset}`;
    }
  }

  return await client.executeQuery(sql);
}

// Old functions removed - use unified entity functions instead:
// - listGroups -> listEntities('group', filters, orderBy, limit, offset)

/**
 * List memberships with optional filtering
 */
export async function listMemberships(
  context: ToolContext,
  filters?: Filter[],
  orderBy?: OrderBy[],
  limit?: number,
  offset?: number
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();

  const relationshipsTable = getQualifiedTableName(
    models.relationships,
    adapterType
  );

  const baseFilters: Filter[] = [
    { column: "relationship_type", operator: "=", value: "membership" },
  ];
  if (filters) {
    baseFilters.push(...filters);
  }

  const sql = buildDynamicSQL({
    table: relationshipsTable,
    filters: baseFilters,
    orderBy: orderBy || [{ column: "established_at", direction: "DESC" }],
    limit,
    offset,
  });

  return await client.executeQuery(sql);
}

/**
 * Get trait history for an entity
 * Returns all historical values of a specific trait for an entity
 */
export async function getTraitHistory(
  context: ToolContext,
  entityId: string,
  traitName: string,
  orderBy?: OrderBy[],
  limit?: number
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();
  const startTime = Date.now();

  const entityTraitsTable = getQualifiedTableName(
    models.entityTraits,
    adapterType
  );
  const eventsTable = getQualifiedTableName(models.events, adapterType);

  // We need to join entity_traits to resolved identifiers to get entity_id
  // Then filter by entity_id and trait_name
  // Also join with events to get event details
  const resolvedPersonIdentifiers = getQualifiedTableName(
    models.resolvedPersonIdentifiers,
    adapterType
  );
  const resolvedGroupIdentifiers = getQualifiedTableName(
    models.resolvedGroupIdentifiers,
    adapterType
  );

  // Build SQL to get trait history by joining entity_traits to resolved identifiers and events
  let sql = `
    SELECT 
      t.entity_trait_id,
      t.event_id,
      t.entity_type,
      t.identifier_type,
      t.identifier_value,
      t.trait_name,
      t.trait_value,
      t.source,
      t.occurred_at,
      COALESCE(pi.person_id, gi.group_id) as entity_id,
      e.event_name,
      e.event_description,
      e.source as event_source,
      e.occurred_at as event_occurred_at
    FROM ${entityTraitsTable} t
    LEFT JOIN ${resolvedPersonIdentifiers} pi 
      ON t.identifier_type = pi.identifier_type
      AND t.identifier_value = pi.identifier_value
      AND t.entity_type = 'person'
    LEFT JOIN ${resolvedGroupIdentifiers} gi 
      ON t.identifier_type = gi.identifier_type
      AND t.identifier_value = gi.identifier_value
      AND t.entity_type = 'group'
    LEFT JOIN ${eventsTable} e
      ON t.event_id = e.event_id
    WHERE COALESCE(pi.person_id, gi.group_id) = '${escapeSQLString(entityId)}'
      AND t.trait_name = '${escapeSQLString(traitName)}'
  `;

  // Add ORDER BY
  if (orderBy && orderBy.length > 0) {
    const clauses = orderBy.map(
      (order) => `${order.column} ${order.direction}`
    );
    sql += ` ORDER BY ${clauses.join(", ")}`;
  } else {
    sql += ` ORDER BY t.occurred_at DESC`;
  }

  // Add LIMIT
  if (limit !== undefined) {
    sql += ` LIMIT ${limit}`;
  }

  console.error("📊 Getting trait history:", {
    entityId,
    traitName,
    limit,
    orderBy,
  });
  console.error("📝 SQL:", sql.substring(0, 200) + "...");

  const result = await client.executeQuery(sql);
  const executionTime = Date.now() - startTime;

  console.error("✅ Trait history retrieved:", {
    rowCount: result.rowCount,
    executionTime: `${executionTime}ms`,
  });

  return result;
}

/**
 * Get edges for an entity (person or group)
 * Returns all edges (connections between identifiers) for an entity, with associated event information
 */
export async function getEdgesForEntity(
  context: ToolContext,
  entityId: string,
  entityType?: "person" | "group",
  orderBy?: OrderBy[],
  limit?: number
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();
  const startTime = Date.now();

  const edgesTable = getQualifiedTableName(
    models.entityIdentifiersEdges,
    adapterType
  );
  const identifiersTable = getQualifiedTableName(
    models.entityIdentifiers,
    adapterType
  );
  const eventsTable = getQualifiedTableName(models.events, adapterType);
  const resolvedPersonIdentifiers = getQualifiedTableName(
    models.resolvedPersonIdentifiers,
    adapterType
  );
  const resolvedGroupIdentifiers = getQualifiedTableName(
    models.resolvedGroupIdentifiers,
    adapterType
  );

  // Determine which resolved identifiers table to use based on entity type
  let resolvedIdentifiersTable: string;
  let resolvedIdColumn: string;

  if (entityType === "group") {
    resolvedIdentifiersTable = resolvedGroupIdentifiers;
    resolvedIdColumn = "group_id";
  } else {
    // Default to person or try both if not specified
    resolvedIdentifiersTable = resolvedPersonIdentifiers;
    resolvedIdColumn = "person_id";
  }

  // Build SQL to get edges for an entity
  // 1. Get all identifiers for the entity
  // 2. Find edges where those identifiers appear (as identifier_a or identifier_b)
  // 3. Join with entity_identifiers to get event_id for each edge
  // 4. Join with events to get event details
  let sql = `
    WITH entity_identifiers AS (
      SELECT DISTINCT
        identifier_type,
        identifier_value
      FROM ${resolvedIdentifiersTable}
      WHERE ${resolvedIdColumn} = '${escapeSQLString(entityId)}'
    ),
    edges_for_entity AS (
      SELECT DISTINCT
        e.edge_id,
        e.entity_type_a,
        e.identifier_type_a,
        e.identifier_value_a,
        e.entity_type_b,
        e.identifier_type_b,
        e.identifier_value_b,
        e.source as edge_source
      FROM ${edgesTable} e
      INNER JOIN entity_identifiers ei ON (
        (e.identifier_type_a = ei.identifier_type AND e.identifier_value_a = ei.identifier_value)
        OR
        (e.identifier_type_b = ei.identifier_type AND e.identifier_value_b = ei.identifier_value)
      )
      WHERE (e.entity_type_a = '${
        entityType || "person"
      }' AND e.entity_type_b = '${entityType || "person"}')
        OR (e.entity_type_a = '${
          entityType || "group"
        }' AND e.entity_type_b = '${entityType || "group"}')
    ),
    edges_with_events AS (
      SELECT DISTINCT
        efe.edge_id,
        efe.entity_type_a,
        efe.identifier_type_a,
        efe.identifier_value_a,
        efe.entity_type_b,
        efe.identifier_type_b,
        efe.identifier_value_b,
        efe.edge_source,
        ei2.event_id
      FROM edges_for_entity efe
      LEFT JOIN ${identifiersTable} ei2 ON (
        (ei2.identifier_type = efe.identifier_type_a AND ei2.identifier_value = efe.identifier_value_a)
        OR
        (ei2.identifier_type = efe.identifier_type_b AND ei2.identifier_value = efe.identifier_value_b)
      )
      AND ei2.edge_id = efe.edge_id
      AND ei2.entity_type = '${entityType || "person"}'
    )
    SELECT 
      ewe.edge_id,
      ewe.entity_type_a,
      ewe.identifier_type_a,
      ewe.identifier_value_a,
      ewe.entity_type_b,
      ewe.identifier_type_b,
      ewe.identifier_value_b,
      ewe.edge_source,
      ewe.event_id,
      e.event_name,
      e.event_description,
      e.source as event_source,
      e.occurred_at as event_occurred_at
    FROM edges_with_events ewe
    LEFT JOIN ${eventsTable} e ON ewe.event_id = e.event_id
    WHERE ewe.event_id IS NOT NULL
  `;

  // Add ORDER BY
  if (orderBy && orderBy.length > 0) {
    const clauses = orderBy.map(
      (order) => `${order.column} ${order.direction}`
    );
    sql += ` ORDER BY ${clauses.join(", ")}`;
  } else {
    sql += ` ORDER BY e.occurred_at DESC`;
  }

  // Add LIMIT
  if (limit !== undefined) {
    sql += ` LIMIT ${limit}`;
  }

  console.error("🔗 Getting edges for entity:", {
    entityId,
    entityType,
    limit,
    orderBy,
  });
  console.error("📝 SQL:", sql.substring(0, 200) + "...");

  const result = await client.executeQuery(sql);
  const executionTime = Date.now() - startTime;

  console.error("✅ Edges retrieved:", {
    rowCount: result.rowCount,
    executionTime: `${executionTime}ms`,
  });

  return result;
}

/**
 * Find edges by identifier value (email, phone, etc.)
 * Returns all edges where the identifier appears, with associated event information
 */
export async function findEdgesByIdentifier(
  context: ToolContext,
  identifierValue: string,
  identifierType?: string,
  entityType?: "person" | "group",
  filters?: Filter[],
  orderBy?: OrderBy[],
  limit?: number
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();
  const startTime = Date.now();

  const edgesTable = getQualifiedTableName(
    models.entityIdentifiersEdges,
    adapterType
  );
  const identifiersTable = getQualifiedTableName(
    models.entityIdentifiers,
    adapterType
  );
  const eventsTable = getQualifiedTableName(models.events, adapterType);

  // Build SQL to find edges by identifier value
  // Match identifier_value in either identifier_value_a or identifier_value_b
  let sql = `
    SELECT DISTINCT
      e.edge_id,
      e.entity_type_a,
      e.identifier_type_a,
      e.identifier_value_a,
      e.entity_type_b,
      e.identifier_type_b,
      e.identifier_value_b,
      e.source as edge_source,
      ei.event_id,
      ev.event_name,
      ev.event_description,
      ev.source as event_source,
      ev.occurred_at as event_occurred_at
    FROM ${edgesTable} e
    LEFT JOIN ${identifiersTable} ei ON (
      (ei.identifier_type = e.identifier_type_a AND ei.identifier_value = e.identifier_value_a)
      OR
      (ei.identifier_type = e.identifier_type_b AND ei.identifier_value = e.identifier_value_b)
    )
    AND ei.edge_id = e.edge_id
    LEFT JOIN ${eventsTable} ev ON ei.event_id = ev.event_id
    WHERE (
      (e.identifier_value_a = '${escapeSQLString(identifierValue)}'
        ${identifierType ? `AND e.identifier_type_a = '${escapeSQLString(identifierType)}'` : ""}
        ${entityType ? `AND e.entity_type_a = '${entityType}'` : ""})
      OR
      (e.identifier_value_b = '${escapeSQLString(identifierValue)}'
        ${identifierType ? `AND e.identifier_type_b = '${escapeSQLString(identifierType)}'` : ""}
        ${entityType ? `AND e.entity_type_b = '${entityType}'` : ""})
    )
  `;

  // Add additional filters
  if (filters && filters.length > 0) {
    const conditions = filters.map((filter) => buildWhereCondition(filter));
    sql += ` AND ${conditions.join(" AND ")}`;
  }

  // Add ORDER BY
  if (orderBy && orderBy.length > 0) {
    const clauses = orderBy.map(
      (order) => `${order.column} ${order.direction}`
    );
    sql += ` ORDER BY ${clauses.join(", ")}`;
  } else {
    sql += ` ORDER BY ev.occurred_at DESC`;
  }

  // Add LIMIT
  if (limit !== undefined) {
    sql += ` LIMIT ${limit}`;
  }

  console.error("🔍 Finding edges by identifier:", {
    identifierValue,
    identifierType,
    entityType,
    limit,
  });
  console.error("📝 SQL:", sql.substring(0, 200) + "...");

  const result = await client.executeQuery(sql);
  const executionTime = Date.now() - startTime;

  console.error("✅ Edges found:", {
    rowCount: result.rowCount,
    executionTime: `${executionTime}ms`,
  });

  return result;
}

/**
 * Search/filter edges with flexible filtering
 * Supports filtering by source, identifier type, entity type, etc.
 */
export async function searchEdges(
  context: ToolContext,
  filters?: Filter[],
  orderBy?: OrderBy[],
  limit?: number,
  offset?: number
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();

  const edgesTable = getQualifiedTableName(
    models.entityIdentifiersEdges,
    adapterType
  );

  // Use buildDynamicSQL for flexible filtering
  const sql = buildDynamicSQL({
    table: edgesTable,
    filters,
    orderBy: orderBy || [{ column: "edge_id", direction: "ASC" }],
    limit,
    offset,
  });

  console.error("🔍 Searching edges:", {
    filterCount: filters?.length || 0,
    limit,
    offset,
  });

  return await client.executeQuery(sql);
}

/**
 * Find edges with quality issues (high connection counts)
 * Returns identifiers with connection counts exceeding the threshold
 */
export async function findEdgesWithQualityIssues(
  context: ToolContext,
  minConnections: number = 20,
  identifierType?: string,
  entityType?: "person" | "group",
  source?: string,
  orderBy?: OrderBy[],
  limit: number = 500
): Promise<QueryResult> {
  const { client, models } = context;
  const adapterType = client.getAdapterType();
  const startTime = Date.now();

  const edgesTable = getQualifiedTableName(
    models.entityIdentifiersEdges,
    adapterType
  );

  // Build WHERE conditions for filters
  let whereConditions: string[] = [];
  if (identifierType) {
    whereConditions.push(
      `identifier_type_a = '${escapeSQLString(identifierType)}'`
    );
  }
  if (entityType) {
    whereConditions.push(`entity_type_a = '${entityType}'`);
  }
  if (source) {
    whereConditions.push(`source = '${escapeSQLString(source)}'`);
  }
  const whereClause =
    whereConditions.length > 0
      ? `WHERE ${whereConditions.join(" AND ")}`
      : "";

  // Build SQL to find identifiers with high connection counts
  let sql = `
    WITH edge_distribution AS (
      SELECT
        entity_type_a,
        identifier_type_a,
        identifier_value_a,
        COUNT(DISTINCT identifier_value_b) as unique_connections
      FROM ${edgesTable}
      ${whereClause}
      GROUP BY entity_type_a, identifier_type_a, identifier_value_a
    )
    SELECT
      entity_type_a,
      identifier_type_a,
      identifier_value_a,
      unique_connections
    FROM edge_distribution
    WHERE unique_connections > ${minConnections}
  `;

  // Add ORDER BY
  if (orderBy && orderBy.length > 0) {
    const clauses = orderBy.map(
      (order) => `${order.column} ${order.direction}`
    );
    sql += ` ORDER BY ${clauses.join(", ")}`;
  } else {
    sql += ` ORDER BY unique_connections DESC`;
  }

  // Add LIMIT (default 500 if not specified)
  sql += ` LIMIT ${limit}`;

  console.error("🔍 Finding edges with quality issues:", {
    minConnections,
    identifierType,
    entityType,
    source,
    limit,
  });
  console.error("📝 SQL:", sql.substring(0, 200) + "...");

  const result = await client.executeQuery(sql);
  const executionTime = Date.now() - startTime;

  console.error("✅ Quality issues found:", {
    rowCount: result.rowCount,
    executionTime: `${executionTime}ms`,
  });

  return result;
}

/**
 * Escape SQL string to prevent injection
 */
function escapeSQLString(str: string): string {
  return str.replace(/'/g, "''");
}
