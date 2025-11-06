import { BigQuery } from "@google-cloud/bigquery";
import { readFileSync } from "fs";
import type { DbtTarget, QueryResult } from "./types.js";

export interface WarehouseClient {
  executeQuery(query: string): Promise<QueryResult>;
  getAdapterType(): "bigquery" | "snowflake";
}

/**
 * Create warehouse client from dbt target configuration
 */
export function createWarehouseClient(target: DbtTarget): WarehouseClient {
  const adapterType = target.type.toLowerCase();

  if (adapterType === "bigquery") {
    return new BigQueryClient(target);
  } else if (adapterType === "snowflake") {
    return new SnowflakeClient(target);
  } else {
    throw new Error(`Unsupported warehouse type: ${target.type}`);
  }
}

/**
 * BigQuery warehouse client
 */
class BigQueryClient implements WarehouseClient {
  private client: BigQuery;
  private projectId: string;

  constructor(target: DbtTarget) {
    this.projectId = target.project || target.dataset?.split(".")[0] || "";

    if (!this.projectId) {
      throw new Error("BigQuery project ID is required");
    }

    // Initialize BigQuery client
    // Support both keyfile and keyfile_json authentication methods
    const config: any = {
      projectId: this.projectId,
    };

    if (target.method === "service-account") {
      if (target.keyfile_json) {
        config.credentials = typeof target.keyfile_json === "string"
          ? JSON.parse(target.keyfile_json)
          : target.keyfile_json;
      } else if (target.keyfile) {
        // keyfile is a path to a JSON file
        const keyfileContent = readFileSync(target.keyfile, "utf-8");
        config.credentials = JSON.parse(keyfileContent);
      } else {
        throw new Error("BigQuery authentication requires keyfile or keyfile_json");
      }
    }
    // If method is "oauth" or not specified, use default application credentials

    this.client = new BigQuery(config);
  }

  getAdapterType(): "bigquery" {
    return "bigquery";
  }

  async executeQuery(query: string): Promise<QueryResult> {
    const startTime = Date.now();
    console.error("🔍 Executing BigQuery query:", {
      queryLength: query.length,
      queryPreview: query.substring(0, 200) + "...",
    });

    try {
      const [rows] = await this.client.query(query);
      const executionTime = Date.now() - startTime;

      console.error("✅ Query executed successfully:", {
        rowCount: rows.length,
        executionTime,
        sampleFields: rows.length > 0 ? Object.keys(rows[0]).slice(0, 5) : [],
      });

      // Convert BigQuery-specific types to plain objects
      const convertedRows = rows.map((row: any) => {
        const convertedRow: any = {};
        for (const [key, value] of Object.entries(row)) {
          if (value && typeof value === "object" && "value" in value) {
            // BigQuery timestamp/datetime objects have a 'value' property
            convertedRow[key] = (value as any).value;
          } else {
            convertedRow[key] = value;
          }
        }
        return convertedRow;
      });

      return {
        data: convertedRows,
        executedAt: Date.now(),
        executionTime,
        rowCount: convertedRows.length,
        query,
      };
    } catch (error: any) {
      console.error("❌ BigQuery query error:", error.message);
      throw new Error(`BigQuery query failed: ${error.message}`);
    }
  }
}

/**
 * Snowflake warehouse client
 */
class SnowflakeClient implements WarehouseClient {
  private config: any;
  private database: string;
  private schema: string;

  constructor(target: DbtTarget) {
    this.database = target.database || "";
    this.schema = target.schema || "";

    if (!target.account || !target.user) {
      throw new Error("Snowflake account and user are required");
    }

    if (!target.warehouse || !this.database || !this.schema) {
      throw new Error("Snowflake warehouse, database, and schema are required");
    }

    this.config = {
      account: target.account,
      username: target.user,
      warehouse: target.warehouse,
      database: this.database,
      schema: this.schema,
    };

    // Determine authentication method
    // Use key-pair auth if private_key_path is provided (authenticator field is optional)
    const useKeyPairAuth = !!target.private_key_path;

    if (!useKeyPairAuth && !target.password) {
      throw new Error(
        "Snowflake password is required when not using key-pair authentication"
      );
    }

    if (useKeyPairAuth) {
      const privateKey = readFileSync(target.private_key_path!, "utf-8");
      this.config.authenticator = "SNOWFLAKE_JWT";
      this.config.privateKey = privateKey;
      if (target.private_key_passphrase) {
        this.config.privateKeyPass = target.private_key_passphrase;
      }
    } else {
      this.config.password = target.password;
    }
  }

  getAdapterType(): "snowflake" {
    return "snowflake";
  }

  async executeQuery(query: string): Promise<QueryResult> {
    const startTime = Date.now();
    console.error("🔍 Executing Snowflake query:", {
      queryLength: query.length,
      queryPreview: query.substring(0, 200) + "...",
    });

    // Transform SQL from BigQuery format to Snowflake format
    const transformedQuery = this.transformSQLForSnowflake(query);

    console.error("📊 Transformed SQL:", transformedQuery.substring(0, 200) + "...");

    // Dynamically require snowflake-sdk
    const snowflake = await import("snowflake-sdk");
    
    // Handle both default and named exports
    const snowflakeSdk = (snowflake as any).default || snowflake;

    return new Promise<QueryResult>((resolve, reject) => {
      const connection = snowflakeSdk.createConnection(this.config);

      connection.connect((err: any, _conn: any) => {
        if (err) {
          console.error("❌ Snowflake connection error:", err.message);
          reject(new Error(`Snowflake connection failed: ${err.message}`));
          return;
        }

        console.error("✅ Successfully connected to Snowflake");

        connection.execute({
          sqlText: transformedQuery,
          complete: (err: any, stmt: any, rows: any) => {
            if (err) {
              console.error("❌ Snowflake query error:", err.message);
              connection.destroy((destroyErr: any) => {
                if (destroyErr) {
                  console.error("Error closing connection:", destroyErr.message);
                }
              });
              reject(new Error(`Snowflake query failed: ${err.message}`));
              return;
            }

            const executionTime = Date.now() - startTime;

            console.error("✅ Query executed successfully:", {
              rowCount: rows.length,
              executionTime,
              sampleFields: rows.length > 0 ? Object.keys(rows[0]).slice(0, 5) : [],
            });

            // Convert Snowflake result types to plain objects
            // Snowflake returns column names in uppercase, convert to lowercase
            const convertedRows = rows.map((row: any) => {
              const convertedRow: any = {};
              for (const [key, value] of Object.entries(row)) {
                const lowerKey = key.toLowerCase();

                // Convert Date objects to ISO strings
                if (value instanceof Date) {
                  convertedRow[lowerKey] = value.toISOString();
                } else if (
                  value &&
                  typeof value === "object" &&
                  "value" in value
                ) {
                  const wrappedValue = (value as any).value;
                  if (wrappedValue instanceof Date) {
                    convertedRow[lowerKey] = wrappedValue.toISOString();
                  } else {
                    convertedRow[lowerKey] = wrappedValue;
                  }
                } else if (
                  typeof value === "string" &&
                  /_at$|_time$|timestamp/i.test(lowerKey)
                ) {
                  // Try to parse and normalize timestamp strings
                  try {
                    const date = new Date(value);
                    if (!isNaN(date.getTime())) {
                      convertedRow[lowerKey] = date.toISOString();
                    } else {
                      convertedRow[lowerKey] = null;
                    }
                  } catch {
                    convertedRow[lowerKey] = null;
                  }
                } else {
                  convertedRow[lowerKey] = value;
                }
              }
              return convertedRow;
            });

            connection.destroy((destroyErr: any) => {
              if (destroyErr) {
                console.error("Error closing connection:", destroyErr.message);
              } else {
                console.error("✅ Snowflake connection closed");
              }
            });

            resolve({
              data: convertedRows,
              executedAt: Date.now(),
              executionTime,
              rowCount: convertedRows.length,
              query: transformedQuery,
            });
          },
        });
      });
    });
  }

  /**
   * Transform BigQuery-style SQL (backticks) to Snowflake format
   * Handles fully qualified names like `database`.`schema`.`table`
   */
  private transformSQLForSnowflake(query: string): string {
    // Match entire qualified names like `db`.`schema`.`table` as one unit
    // This pattern matches: `identifier` or `identifier`.`identifier` or `identifier`.`identifier`.`identifier` etc.
    const qualifiedNamePattern = /(`[^`]+`(?:\s*\.\s*`[^`]+`)*)/g;

    let transformedQuery = query;

    transformedQuery = transformedQuery.replace(
      qualifiedNamePattern,
      (match) => {
        // Remove all backticks and split by dots
        const cleaned = match.replace(/`/g, "").trim();
        const parts = cleaned.split(/\s*\.\s*/).filter((p: string) => p.length > 0);
        const identifierParts = parts;

        // If already fully qualified (3+ parts: database.schema.table), use as-is
        if (identifierParts.length >= 3) {
          const qualifiedName = identifierParts
            .map((part: string) => `"${part.toUpperCase()}"`)
            .join(".");
          return qualifiedName;
        }
        // If 2 parts (schema.table), add database
        else if (identifierParts.length === 2) {
          const qualifiedName = `"${this.database.toUpperCase()}"."${identifierParts[0].toUpperCase()}"."${identifierParts[1].toUpperCase()}"`;
          return qualifiedName;
        }
        // If 1 part (table only), add database and schema
        else if (identifierParts.length === 1) {
          const qualifiedName = `"${this.database.toUpperCase()}"."${this.schema.toUpperCase()}"."${identifierParts[0].toUpperCase()}"`;
          return qualifiedName;
        }

        return `"${cleaned.toUpperCase()}"`;
      }
    );

    return transformedQuery;
  }
}

