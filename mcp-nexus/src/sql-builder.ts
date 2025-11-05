import type { Filter, OrderBy } from "./types.js";

export interface DynamicSQLOptions {
  table: string;
  filters?: Filter[];
  orderBy?: OrderBy[];
  limit?: number;
  offset?: number;
}

/**
 * Build dynamic SQL query with filters, sorting, and pagination
 */
export function buildDynamicSQL(options: DynamicSQLOptions): string {
  let sql = `SELECT * FROM ${options.table}`;

  // Add WHERE clause if filters exist
  if (options.filters && options.filters.length > 0) {
    const whereConditions = options.filters.map((filter) => {
      return buildWhereCondition(filter);
    });
    sql += ` WHERE ${whereConditions.join(" AND ")}`;
  }

  // Add ORDER BY clause
  if (options.orderBy && options.orderBy.length > 0) {
    const orderClauses = options.orderBy.map(
      (order) => `${order.column} ${order.direction}`
    );
    sql += ` ORDER BY ${orderClauses.join(", ")}`;
  }

  // Add LIMIT and OFFSET
  if (options.limit !== undefined) {
    sql += ` LIMIT ${options.limit}`;
  }
  if (options.offset !== undefined && options.offset > 0) {
    sql += ` OFFSET ${options.offset}`;
  }

  return sql;
}

/**
 * Build WHERE condition from filter
 */
export function buildWhereCondition(filter: Filter): string {
  const { column, operator, value } = filter;

  switch (operator) {
    case "IS NULL":
    case "IS NOT NULL":
      return `${column} ${operator}`;

    case "IN":
      if (Array.isArray(value)) {
        const values = value
          .map((v) => {
            if (v === null || v === undefined) {
              return "NULL";
            }
            return typeof v === "string" ? `'${escapeSQLString(v)}'` : String(v);
          })
          .join(", ");
        return `${column} IN (${values})`;
      }
      throw new Error("IN operator requires array value");

    case "LIKE":
      if (value === null || value === undefined) {
        throw new Error("LIKE operator requires a value");
      }
      return `${column} LIKE '${escapeSQLString(String(value))}'`;

    default:
      if (value === null || value === undefined) {
        throw new Error(`${operator} operator requires a value`);
      }
      const formattedValue =
        typeof value === "string" ? `'${escapeSQLString(value)}'` : String(value);
      return `${column} ${operator} ${formattedValue}`;
  }
}

/**
 * Escape SQL string to prevent injection
 */
function escapeSQLString(str: string): string {
  return str.replace(/'/g, "''");
}

/**
 * Build WHERE clause from multiple filters
 */
export function buildWhereClause(filters: Filter[]): string {
  if (filters.length === 0) {
    return "";
  }
  const conditions = filters.map((filter) => buildWhereCondition(filter));
  return `WHERE ${conditions.join(" AND ")}`;
}

/**
 * Build ORDER BY clause from order specs
 */
export function buildOrderByClause(orderBy: OrderBy[]): string {
  if (orderBy.length === 0) {
    return "";
  }
  const clauses = orderBy.map(
    (order) => `${order.column} ${order.direction}`
  );
  return `ORDER BY ${clauses.join(", ")}`;
}

/**
 * Build LIMIT/OFFSET clause
 */
export function buildLimitClause(limit?: number, offset?: number): string {
  let clause = "";
  if (limit !== undefined) {
    clause += ` LIMIT ${limit}`;
  }
  if (offset !== undefined && offset > 0) {
    clause += ` OFFSET ${offset}`;
  }
  return clause;
}

