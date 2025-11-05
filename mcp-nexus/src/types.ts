export interface DbtProfile {
  name: string;
  target?: string;
  outputs: {
    [key: string]: DbtTarget;
  };
}

export interface DbtTarget {
  type: string;
  method?: string;
  project?: string;
  dataset?: string;
  location?: string;
  keyfile?: string;
  keyfile_json?: string;
  account?: string;
  user?: string;
  password?: string;
  authenticator?: string;
  private_key_path?: string;
  private_key_passphrase?: string;
  warehouse?: string;
  database?: string;
  schema?: string;
  [key: string]: any;
}

export interface DbtProject {
  name: string;
  profile?: string;
  target?: string;
  [key: string]: any;
}

export interface NexusModels {
  entities: string;
  relationships: string;
  events: string;
  entityParticipants: string;
  entityTraits: string;
  entityIdentifiers: string;
  entityIdentifiersEdges: string;
  resolvedPersonIdentifiers: string;
  resolvedGroupIdentifiers: string;
  schema: string;
}

export interface QueryResult {
  data: any[];
  executedAt: number;
  executionTime: number;
  rowCount: number;
  query?: string;
}

export interface Filter {
  column: string;
  operator: "=" | "!=" | ">" | "<" | ">=" | "<=" | "LIKE" | "IN" | "IS NULL" | "IS NOT NULL";
  value?: any;
}

export interface OrderBy {
  column: string;
  direction: "ASC" | "DESC";
}

export interface DbtConfig {
  project: DbtProject;
  profile: DbtProfile;
  target: DbtTarget;
  projectDir: string;
  profilesDir: string;
}

export interface WarehouseClient {
  executeQuery(query: string): Promise<QueryResult>;
  getAdapterType(): "bigquery" | "snowflake";
}

export interface ToolContext {
  client: WarehouseClient;
  models: NexusModels;
}

