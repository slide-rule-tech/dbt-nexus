# Headless CRM Data Warehouse

## Overview

This document describes the data architecture for our headless CRM system built
using dbt. The system processes data from various sources into a unified
customer data platform with identity resolution.

## Data Flow Architecture

The data warehouse is organized into five primary layers:

1. **Raw Data** - Source data ingested from external systems with minimal
   transformation
2. **Source Event Log** - Normalized source-specific events and identifiers
3. **Core Event Log** - Unified events with standardized schema across sources
4. **Identity Resolution** - Resolved identities and attributes across sources
5. **Final Tables** - Production tables for application use

### Raw Data Layer

The Raw Data layer handles direct ingestion from source systems with minimal
transformations:

- Reads directly from source tables in the data warehouse
- Applies incremental filtering based on `synced_at`
- Preserves the original data structure
- Adds `_ingested_at` to track when dbt processed each row
- Typically follows the pattern `<source_name>_<entity>_raw.sql`

This layer provides a clean foundation for all downstream models and isolates
them from changes in the source data structure.

## Data Model Diagram

The project contains a database diagram (`database-diagram.xml`) created with
draw.io that visually represents the data flow and relationships between the
different entities in the headless CRM. This diagram shows how data moves from
source systems through the transformation layers to the final resolved entities.

To view or edit the diagram:

1. Open the `database-diagram.xml` file using
   [draw.io](https://app.diagrams.net/)
2. The diagram illustrates the connections between source events, identifiers,
   and traits through the identity resolution process
3. Use this as a reference when adding new data sources or modifying the data
   model

## Raw Data Sources

Our initial raw data source is Shopify Partner app events, which provide
information about app installations, charges, and other partner-related
activities.

### Shopify Partner App Events

Source data is loaded from the `shopify_partner_app_events.sql` model, which:

- Extracts and parses JSON fields from raw Shopify Partner API data
- Performs type casting and timestamp normalization
- Deduplicates events based on event_id

## Source Events Format

All source events follow a standardized format with these core columns (in
order):

- **id** - Unique identifier for the event (UUID)
- **occurred_at** - Timestamp when the event occurred
- **event_name** - Specific event name (e.g., 'app_installed', 'charge_created')
- **event_description** - Human-readable description (e.g., 'Store Name
  app_installed App Name')
- **value** - Numeric value associated with the event (if applicable)
- **value_unit** - Unit of the value field (e.g., 'USD')
- **event_type** - Category of the event (e.g., 'app_event')
- **source** - The source system that generated the event (e.g.,
  'shopify_partner')

Additional source-specific fields may be included as needed.

## Source Event Log Implementation

The Source Event Log layer translates raw data into a standardized format while
preserving source-specific details. For each data source, we create specific
models:

### Events Models

Events models (e.g., `shopify_partner_events.sql`) follow this pattern:

```sql
WITH source_data AS (
    SELECT
        /* Reference the raw data model */
        FROM {{ ref('source_raw_data_model') }}
)

SELECT
    -- Primary Key
    id,
    -- Standard event fields
    occurred_at,
    event_name,
    event_description,
    value,
    value_unit,
    -- Metadata
    event_type,
    source,
    -- Any additional source-specific fields
FROM source_data
```

Source event models include all custom fields specific to that source, while the
core events model (`events.sql`) only includes the standard fields. This
approach keeps the core events table narrow and standardized while still
allowing access to all source-specific details by joining back to the source
event models when needed.

The core events model uses dbt_utils.union_relations to combine events from
different sources while only including the standard fields:

```sql
with unioned as (
    {{ dbt_utils.union_relations(
        relations=[
            ref('shopify_partner_events'),
            ref('gadget_events')
        ],
        include=[
            'id',
            'occurred_at',
            'event_type',
            'event_name',
            'event_description',
            'value',
            'value_unit',
            'source',
        ]
    ) }}
)
```

### Identifier Models

Group identifier models (e.g., `shopify_partner_group_identifiers.sql`) capture
unique identifiers for organizations:

```sql
WITH source_data AS (
    SELECT *
    FROM {{ ref('source_raw_data_model') }}
)

SELECT
    /* Generate unique identifier for the group identifier record */
    {{ dbt_utils.generate_surrogate_key(['event_id', 'identifier_field']) }} as id,
    event_id,
    /* Source-specific identifiers (e.g., domain, shop_id) */
FROM source_data
```

### Traits Models

Group trait models (e.g., `shopify_partner_group_traits.sql`) capture attributes
about organizations:

```sql
WITH source_data AS (
    SELECT *
    FROM {{ ref('source_raw_data_model') }}
)

SELECT
    /* Link to the group identifier */
    {{ dbt_utils.generate_surrogate_key(['event_id', 'identifier_fields']) }} as group_identifiers_id,
    event_id,
    /* Trait fields (e.g., name, industry) */
FROM source_data
```

Each source follows this pattern, ensuring consistent structure while
accommodating source-specific details.

### Naming Convention

For Source Event Log layer files, follow these naming patterns:

- Events: `<source_name>_events.sql` (e.g., `shopify_partner_events.sql`)
- Group Identifiers: `<source_name>_group_identifiers.sql` (e.g.,
  `shopify_partner_group_identifiers.sql`)
- Group Traits: `<source_name>_group_traits.sql` (e.g.,
  `shopify_partner_group_traits.sql`)
- Person Identifiers: `<source_name>_person_identifiers.sql` (e.g.,
  `shopify_partner_person_identifiers.sql`)
- Person Traits: `<source_name>_person_traits.sql` (e.g.,
  `shopify_partner_person_traits.sql`)
- Membership Identifiers: `<source_name>_membership_identifiers.sql` (e.g.,
  `gadget_membership_identifiers.sql`)

These models should be placed in a `models/<source_name>/events/` directory
structure to maintain organization.

## Data Model Entities

### Source Layer

- **source_events** - Raw events from each source system
- **source_person_identifiers** - Source-specific person identifiers (email,
  etc.)
- **source_person_traits** - Source-specific person attributes
- **source_group_identifiers** - Source-specific group identifiers (domain,
  etc.)
- **source_group_traits** - Source-specific group attributes
- **source_membership_identifiers** - Source-specific relationships between
  persons and groups

### Core Layer

- **events** - Unified event format across all sources with standardized schema
- **person_identifiers** - Normalized person identifiers with source attribution
- **group_identifiers** - Normalized group identifiers with source attribution
- **membership_identifiers** - Links between persons and groups with
  relationship metadata

### Identity Resolution Layer

- **resolved_person_identifiers** - Deduplicated person identifiers
- **resolved_person_traits** - Consolidated person attributes
- **resolved_group_identifiers** - Deduplicated group identifiers
- **resolved_group_traits** - Consolidated group attributes
- **resolved_membership_identifiers** - Resolved person-group relationships with
  metadata

### Final Tables Layer

- **persons** - Production person records with latest attributes
- **groups** - Production group/company records
- **memberships** - Production person-group relationships

## Implementation with dbt

The implementation uses dbt for transformation with the following pattern:

1. **Sources**: Define external source tables using dbt sources
2. **Staging**: Initial parsing and type conversion of raw data
3. **Intermediate**: Business logic transformations and relationship mapping
4. **Final**: Production tables with resolved entities

## Identity Resolution Process

The identity resolution system:

1. Collects identifiers from all sources
2. Establishes identifier relationships
3. Resolves entities based on connected identifiers
4. Merges attributes from all sources
5. Maintains source provenance

### Identifier Unpivoting in Source Models

All source identifier models (e.g., `manual_person_identifiers.sql`) must follow
a consistent pattern to enable effective identity resolution:

1. **Standardized Output Schema**: Each model must produce outputs with these
   essential columns:

   - `event_id` - Reference to the source event
   - `row_id` - Surrogate key that groups related identifiers from the same
     record/entity
   - `identifier_type` - String categorizing the type of identifier (e.g.,
     'email', 'phone')
   - `identifier_value` - The actual identifier value
   - Metadata columns: `source`, `source_table`, `occurred_at`, etc.

2. **Unpivoting Identifiers**: Source models must transform source-specific
   structured data into the type-value pairs:

```sql
-- Example: Unpivoting identifiers from a JSON structure
identifiers_unpivoted AS (
    SELECT
        event_id,
        row_id,
        'email' as identifier_type,
        JSON_EXTRACT_SCALAR(identifiers, '$.email') as identifier_value,
        -- metadata columns
    FROM identifiers_with_row_id
    WHERE JSON_EXTRACT_SCALAR(identifiers, '$.email') IS NOT NULL

    UNION ALL

    SELECT
        event_id,
        row_id,
        'phone' as identifier_type,
        JSON_EXTRACT_SCALAR(identifiers, '$.phone') as identifier_value,
        -- metadata columns
    FROM identifiers_with_row_id
    WHERE JSON_EXTRACT_SCALAR(identifiers, '$.phone') IS NOT NULL
)
```

3. **Row ID Generation**: A critical part of this process is generating a
   `row_id` that groups related identifiers from the same record. This enables
   the identity graph to understand when multiple identifiers are explicitly
   connected:

```sql
-- Generate a row_id to group related identifiers
SELECT
    event_id,
    {{ dbt_utils.generate_surrogate_key(['event_id', 'person_position']) }} as row_id,
    -- other fields
FROM extracted_identifiers
```

This standardized approach ensures all source models consistently produce
identifier data that can be processed by downstream identity resolution models.

### Edge Generation and Deduplication

A critical step in identity resolution is creating and deduplicating edges
between identifiers. An edge represents a connection between two different
identifiers that belong to the same entity.

#### The Edge Deduplication Challenge

The system faces several challenges when creating edges:

- The same logical edge might appear multiple times across events
- Edges may appear in different orders (A→B or B→A) but represent the same
  connection
- We need to process only new data in each incremental run while still
  deduplicating globally

#### Edge Normalization and Deduplication Pattern

We use a reusable macro (`create_and_dedup_edges`) that implements this pattern:

1. **Generate initial edge pairs**:

   ```sql
   select
     a.event_id,
     a.row_id,
     a.identifier_type as identifier_type_a,
     a.identifier_value as identifier_value_a,
     b.identifier_type as identifier_type_b,
     b.identifier_value as identifier_value_b
   from identifiers a
   join identifiers b
     on a.row_id = b.row_id
     and (a.identifier_type != b.identifier_type or a.identifier_value != b.identifier_value)
   ```

2. **Normalize edges to eliminate order-based duplicates** (making A→B and B→A
   identical):

   ```sql
   select
     least(identifier_type_a, identifier_type_b) as identifier_type_a,
     case
       when identifier_type_a = identifier_type_b then least(identifier_value_a, identifier_value_b)
       when identifier_type_a < identifier_type_b then identifier_value_a
       else identifier_value_b
     end as identifier_value_a,
     greatest(identifier_type_a, identifier_type_b) as identifier_type_b,
     case
       when identifier_type_a = identifier_type_b then greatest(identifier_value_a, identifier_value_b)
       when identifier_type_a < identifier_type_b then identifier_value_b
       else identifier_value_a
     end as identifier_value_b
   ```

3. **Generate a deterministic edge_id** for each normalized edge:

   ```sql
   {{ dbt_utils.generate_surrogate_key(['least(identifier_type_a, identifier_type_b)',
                                       'greatest(identifier_type_a, identifier_type_b)',
                                       '...normalized identifier_value_a...',
                                       '...normalized identifier_value_b...']) }} as edge_id
   ```

4. **Deduplicate and preserve the earliest provenance**:
   ```sql
   select
     edge_id,
     identifier_type_a,
     identifier_value_a,
     identifier_type_b,
     identifier_value_b,
     min(occurred_at) as occurred_at,  -- When this edge was first established
     min(source) as source              -- Source of the earliest occurrence
     -- other metadata
   from normalized_edges
   group by
     edge_id,
     identifier_type_a,
     identifier_value_a,
     identifier_type_b,
     identifier_value_b
   ```

This pattern ensures:

- Only unique edges exist in the final model
- Edge direction is normalized for consistent entity resolution
- Only new data is processed during incremental runs
- The system maintains correct provenance for each edge

### Trait Resolution

The trait resolution process follows these steps:

1. Source-specific trait models (e.g., `shopify_partner_group_traits.sql`)
   extract traits and their associated identifiers
2. The `group_traits.sql` model unions traits from all sources into a
   standardized format
3. The `unpivot_traits` macro transforms wide-format trait tables into
   long-format records with:
   - Identifier information (type and value)
   - Trait name and value
   - Temporal information (event_id, occurred_at)
4. The `resolved_group_traits.sql` model:
   - Joins traits with resolved group identifiers using (identifier_type,
     identifier_value) pairs
   - No need to track group_identifiers.id IDs through the pipeline
   - Each trait inherits its group's resolved `group_id` through the join
   - Selects the most recent value for each trait per group
   - Maintains the timestamp of when each trait was last updated

This approach ensures that:

- Multiple trait sources can be easily integrated
- Trait history is preserved
- The most recent trait values are always available
- Traits are properly associated with resolved group identities
- No need to maintain ID mappings between traits and groups

## Membership Resolution

Membership resolution is a critical component of our identity resolution system
that establishes relationships between persons and groups/organizations. This
process:

1. Identifies connections between individual identities and organizational
   entities
2. Establishes provenance for each membership relationship
3. Maintains temporal awareness of when memberships and roles change

### Gadget Membership Resolution

The Gadget source provides valuable membership data through the following
process:

1. **Source Extraction**: Membership signals are extracted from Gadget events
   that indicate person-group relationships
2. **Membership Identifier Creation**: Each membership signal generates a record
   in `gadget_membership_identifiers.sql` containing:

   - Person identifier information with explicit type (email)
   - Group identifier information with explicit type (shop_id)
   - Role information (e.g., "owner")
   - Temporal information (event_id, occurred_at)

3. **Resolution Process**:
   - Membership identifiers from Gadget are joined with resolved person and
     group identifiers using both identifier type and value
   - Each membership inherits both its person's resolved `person_id` and its
     group's resolved `group_id` through deterministic joins
   - The most current role information is selected for each person-group pair

This approach ensures that:

- Multiple membership sources can be integrated
- Membership history is preserved
- Current roles are properly reflected
- Memberships are correctly associated with resolved person and group identities

#### Gadget Membership Implementation

For the Gadget source implementation, we will:

1. Create `gadget_membership_identifiers.sql` in the `models/gadget/events/`
   directory that:

   - Captures the relationship between person identifiers (shop owner email) and
     group identifiers (shop_id)
   - Explicitly designates identifier types to avoid ambiguity
   - Records the relationship type ("owner") and event metadata
   - Uses exactly one person identifier and one group identifier to avoid
     conflicts

2. The model will follow this implementation pattern:

   ```sql
   WITH source_data AS (
       SELECT *
       FROM {{ ref('shops') }}
   )

   SELECT
       {{ dbt_utils.generate_surrogate_key(['event_id', 'shop_owner_email', 'shop_id']) }} as id,
       event_id,
       occurred_at,
       shop_owner_email as person_identifier,
       'email' as person_identifier_type,
       shop_id as group_identifier,
       'shop_id' as group_identifier_type,
       'owner' as role,
       'gadget' as source
   FROM source_data
   WHERE shop_owner_email IS NOT NULL
   ```

3. The resolution process directly joins the membership identifiers with
   resolved entities:

   - Uses both identifier type and value for accurate joins
   - Creates direct links between resolved persons and groups
   - Selects the most recent role information for each person-group pair

4. This approach is appropriate because:
   - Using explicit identifier types prevents ambiguity when the same value
     could represent different entity types
   - It supports efficient joins with resolved identifiers
   - It avoids the need for complex unpivoting of identifiers

The resolved memberships are structured like:

```sql
SELECT
    {{ dbt_utils.generate_surrogate_key(['person_id', 'group_id']) }} as id,
    person_id,
    group_id,
    role,
    source,
    occurred_at
FROM joined_memberships
WHERE row_num = 1
```

Where joined_memberships is:

```sql
SELECT
    mi.occurred_at,
    rp.person_id,
    rg.group_id,
    mi.role,
    mi.source,
    row_number() over (
        partition by person_id, group_id
        order by occurred_at desc
    ) as row_num
FROM membership_identifiers mi
JOIN resolved_person_identifiers rp
    ON mi.person_identifier_type = rp.identifier_type
    AND mi.person_identifier = rp.identifier_value
JOIN resolved_group_identifiers rg
    ON mi.group_identifier_type = rg.identifier_type
    AND mi.group_identifier = rg.identifier_value
WHERE rp.person_id IS NOT NULL
  AND rg.group_id IS NOT NULL
```

This approach mirrors how traits are handled in the system while maintaining all
necessary relationship information and ensuring correct entity resolution.

To implement Gadget membership resolution, we create the following models:

- `gadget_membership_identifiers.sql` - Source-specific membership identifiers
- `membership_identifiers.sql` - Standardized membership identifiers from all
  sources
- `resolved_membership_identifiers.sql` - Joined with resolved person and group
  identities
- `memberships.sql` - Final production table with additional display information

## Building and Deploying

To build and run the dbt models:

```bash
dbt run --models source_layer  # Build source layer models
dbt run --models core_layer    # Build core layer models
dbt run --models identity      # Run identity resolution
dbt run --models marts         # Build final tables
```

## Extending with New Sources

To add a new data source:

1. Create a raw data model that directly references the source table

   - Use `incremental_source_filter()` to ensure efficient processing
   - Example: `manual_events_raw.sql`

2. Create a source adapter in the source events layer

   - References the raw model
   - Normalizes fields to the standard schema
   - Example: `manual_events.sql`

3. Add source-specific identifiers and traits models

   - Extract identifiers and attributes from the source data
   - Maintain lineage with `source`, `source_table`
   - Examples: `manual_person_identifiers.sql`, `manual_person_traits.sql`

4. Add the source to the `event_sources` variable in `dbt_project.yml`

   ```yaml
   vars:
     event_sources:
       - name: existing_source_events
         source: existing_source
       - name: new_source_events
         source: new_source
   ```

5. Run the pipeline to incorporate the new data
   - Core models with `union_with_watermarks` will automatically include the new
     source

This approach allows for seamless integration of new sources without modifying
core model SQL.

## Maintenance and Monitoring

- Regular audit of identity resolution quality
- Monitoring for data volume and processing times
- Schema evolution management

## Implementing Near Real-Time Updates with Incremental Models

To achieve the goal of reflecting new events in the final tables within seconds
(near real-time), the primary strategy is to leverage dbt's `incremental`
materialization for most models throughout the pipeline. This minimizes the
amount of data processed during each `dbt run`.

### Key Concepts for Incremental Models

1.  **Materialization:** Set the model's materialization to `incremental` either
    in the `dbt_project.yml` file or within the model's config block:

    ```sql
    {{ config(materialized='incremental') }}
    ```

2.  **Filtering New Data:** The core of an incremental model is filtering data
    to process only new records since the last run. This is done within the
    model's SQL using the `is_incremental()` macro. The filter typically relies
    on a monotonically increasing timestamp or ID.

3.  **Timestamp for Filtering (Different Timestamps for Different Stages):**

    - **Source Models: Using `synced_at`**

      - `synced_at`: Represents when the upstream system ingested this data into
        your warehouse.
      - **Why use `synced_at` for source models?** It's the earliest time this
        data could possibly show up in your dbt pipeline and gives you safe,
        reliable filtering — you won't miss delayed or backfilled records.
      - **Important requirement:** All source tables MUST include a `synced_at`
        timestamp field that reliably indicates when the row was first added to
        the data warehouse. This field is critical for proper incremental
        processing and should be populated by the data ingestion process before
        dbt runs.
      - Example source model filter:
        ```sql
        {% if is_incremental() %}
        where synced_at > (select max(synced_at) from {{ this }})
        {% endif %}
        ```

    - **Downstream Models: Using `_ingested_at`**
      - `_ingested_at`: Added by source models using `current_timestamp()` to
        mark when dbt processed the row.
      - `occurred_at`: Still used within model logic (e.g., window functions
        `ORDER BY occurred_at DESC`) to determine the correct state (like the
        most recent trait value).
      - **Why use `_ingested_at` for downstream models?** When unioning data
        from multiple sources (especially with different sync cadences), using
        `_ingested_at` ensures you process all newly available data regardless
        of its business timestamp (`occurred_at`).
      - **Important:** Always carry the original `synced_at` field through all
        downstream models. While `_ingested_at` is used for filtering,
        preserving `synced_at` provides:
        - Audit trail showing when data first entered the warehouse
        - Ability to analyze data pipeline latency (time between `occurred_at`
          and `synced_at`)
        - Additional filtering options for specific use cases

4.  **Per-Source Watermark Filtering:** When unioning sources with different
    latencies, a single global `max(_ingested_at)` filter is insufficient.
    Instead, apply the filter _per source_ based on the maximum `

#### union_with_watermarks

This macro dynamically generates a UNION ALL statement across multiple source
models, applying per-source watermarking for incremental runs:

```sql
{{ union_with_watermarks(
    sources_var='event_sources',          -- Variable containing source definitions
    source_field='_ingested_at',          -- Field in source models
    target_field='source_ingested_at',    -- Field name in the target model
    override_var='override_incremental',  -- Variable for override
    target_model=this,                    -- Model to compare against
    dev_only=true                         -- Whether override only in dev
) }}
```

**Usage example for events:**

```sql
{{ config(materialized='incremental', unique_key='id') }}

WITH unioned AS (
    {{ union_with_watermarks(sources_var='event_sources') }}
)

SELECT
    id,
    occurred_at,
    -- other fields
    source_ingested_at,
    {{ current_timestamp() }} as _ingested_at
FROM unioned
```

**Usage example for dynamic column sets:**

```sql
{{ config(materialized='incremental', unique_key='id') }}

WITH unioned AS (
    {{ union_with_watermarks(sources_var='person_identifier_sources') }}
)

SELECT
    *,
    {{ current_timestamp() }} as _ingested_at
FROM unioned
```

The macro will automatically:

1. Collect all columns from all source models
2. Create a union query where each source selects all columns (using NULL for
   missing columns)
3. Apply per-source watermark filtering for incremental processing

**Variable structure in dbt_project.yml:**

```yaml
vars:
  event_sources:
    - name: shopify_partner_events
      source: shopify_partner
    - name: manual_events
      source: manual
    # Add more sources as needed

  person_identifier_sources:
    - name: shopify_partner_person_identifiers
      source: shopify_partner
    - name: manual_person_identifiers
      source: manual
```

**Parameters:**

- `sources_var`: Variable name containing source definitions (required)
- `source_field` (default: '\_ingested_at'): Field in source models to use for
  filtering
- `target_field` (default: 'source_ingested_at'): Name to assign to the source
  field in output
- `override_var` (default: 'override_incremental'): Variable to check for
  override
- `target_model` (default: this): Model to compare against
- `dev_only` (default: true): Whether override only applies in dev environment
- `template_relation` (default: none): Optional relation to use as a template
  for column selection (only used with `events_sources`)

**Benefits:**

- Dynamically handles any number of sources defined in variables
- Consistently applies per-source watermarking for each source
- Makes adding/removing sources simple by just updating the variable
- Centralizes the union logic in one place
- Supports both predefined schemas (events) and dynamic column discovery
- Handles schema differences between sources by including all columns across all
  models

## Event Processing Strategy for Real-Time and Batch Operations

Our dbt strategy for event processing is designed to serve both batch and
real-time processing needs through reusable base models. These models define the
transformation logic for each event source (e.g., Gmail, Shopify, manual events)
and transform raw event data into a standardized schema for our CRM.

### Key Characteristics

- **Current Materialization Strategy**: All models are materialized as tables
  for now, since we run nightly full-refresh jobs and don't require incremental
  logic yet.

- **Per-Event Filtering**: Each base model supports per-event filtering using a
  Jinja variable (`event_id`) in the WHERE clause. This allows the same model to
  be compiled at runtime with a specific event_id for real-time processing.

### Implementation Example

Base models include a WHERE clause pattern like:

```sql
WHERE 1=1
  {% if var('event_id', none) %}
    AND id = '{{ var("event_id") }}'
  {% endif %}
```

### Real-Time Processing Flow

1. **Compile with Specific Event ID**:

   ```bash
   dbt compile --vars '{"event_id": "abc123"}'
   ```

2. **Execute from Application**: The compiled SQL is executed directly from our
   Node.js app or GraphQL mutation:
   ```sql
   INSERT INTO crm.processed_events
   SELECT * FROM ( ...compiled SQL with WHERE id = 'abc123'... )
   ```

### Benefits

This dual-purpose setup allows us to:

1. Reuse the same dbt logic consistently in both:

   - Nightly batch jobs via `dbt run`
   - Real-time single-event processing via compiled SQL + parameter injection

2. Maintain a single source of truth for transformation logic

3. Evolve our architecture over time - we can later switch to incremental
   materializations for specific models without changing the real-time
   architecture

## GraphQL Implementation for Real-Time Event Processing

The real-time event processing strategy is implemented in our Apollo GraphQL
server with a mutation called `processEvent`. This mutation provides the bridge
between our application and the dbt-compiled SQL models.

### GraphQL Mutation: processEvent

This mutation is used to process a single event from a specific source (e.g.,
gmail, shopify, or manual). It dynamically compiles the relevant dbt model using
the event ID, filters it, and inserts the result into the appropriate final
table in the CRM.

#### Purpose

- Acts as a real-time processor for a single event
- Bridges Node.js and dbt-compiled SQL
- Enables per-event ingestion without rerunning full dbt jobs

#### Behavior

Given an event source and ID:

1. Looks up the corresponding dbt model and target table from a config map:

   ```typescript
   const PROCESSING_MODELS = {
     gmail: {
       compiledModel: "gmail_event_processed",
       targetTable: "crm.processed_gmail_events",
     },
     manual: {
       compiledModel: "manual_events_base",
       targetTable: "crm.manual_events",
     },
     // ...
   };
   ```

2. Loads the compiled SQL for the dbt model from the `target/compiled/` folder.

3. Wraps it in a filtered insert statement:

   ```sql
   INSERT INTO <targetTable>
   SELECT * FROM (
     -- compiled dbt SQL
   ) AS base
   WHERE id = @event_id
   ```

4. Executes the insert using a SQL client (e.g., BigQuery or Postgres) with
   parameter substitution.

5. Returns metadata (e.g., success status and processedAt timestamp).

#### Notes

- The dbt models support `var('realtime_event_id')` for selective compilation
- This allows each model to be reused for both nightly batch runs and real-time
  processing
- The resolver does not call dbt compile at runtime — it uses precompiled SQL
  stored at deploy time

#### Example Schema

```graphql
type Mutation {
  processEvent(source: String!, id: ID!): ProcessResult
}

type ProcessResult {
  success: Boolean!
  processedAt: String!
}
```

This architecture ensures a clean separation between the transformation logic
(defined in dbt) and the execution environment (Node.js), while maintaining the
performance benefits of real-time processing.

### Advanced Implementation: Sequential Model Execution

Our initial implementation ran a single model with filtering applied at the end.
Our improved approach more closely mimics dbt's native execution model:

1. **Sequential Model Execution**:

   - First runs the base model with filtering
   - Then runs each transformed model in sequence
   - This preserves the dbt execution graph for real-time processing

2. **Early Filtering**:

   - Applies the event ID filter at the base model level
   - Creates a temporary table containing only the filtered data
   - All downstream models operate only on this filtered subset
   - This dramatically improves performance for complex transformations

3. **Model Configuration**:

   ```typescript
   const SOURCE_CONFIGS = {
     manual: {
       baseModel: {
         modelPath: "sources/manual/events/manual_events_base.sql",
         temporaryTable: `${DATASET}.temp_manual_events_base`,
         requiresFilter: true,
       },
       transformedModels: [
         {
           modelPath: "sources/manual/events/manual_events.sql",
           finalTable: `${DATASET}.manual_events`,
           hasJsonRecord: true,
         },
       ],
     },
   };
   ```

4. **DELETE + INSERT Pattern**:

   - Instead of simple inserts or complex merges that require column knowledge
   - First deletes any existing records with the same ID
   - Then inserts the new records
   - This approach effectively implements "upsert" functionality without
     requiring knowledge of specific column names
   - Code example:

     ```sql
     -- Delete existing records with the same ID
     DELETE FROM `target_table`
     WHERE id IN (
       SELECT id FROM (source_query) AS source
     );

     -- Insert new records
     INSERT INTO `target_table`
     source_query;
     ```

5. **Performance Considerations**:
   - The DELETE + INSERT pattern adds some overhead compared to simple appends:
     - Requires two queries instead of one (DELETE then INSERT)
     - The DELETE operation must scan the target table to find matching IDs
     - For very large tables, this scan can be costly in terms of time and
       resources
   - Optimization strategies:
     - Table partitioning (e.g., by date) to limit scan scope
     - Clustering by ID to make DELETE operations more efficient
     - Processing events in small batches to reduce the scan scope
   - When to consider simple appends instead:
     - Events are guaranteed to be inserted only once (no duplicates)
     - You have downstream deduplication processes
     - You're extremely cost/performance sensitive

This enhanced implementation provides a more robust solution that:

- Preserves the dbt model dependency structure
- Applies filtering as early as possible in the chain
- Handles potential duplicates gracefully
- Can be easily extended to include additional models in the execution sequence
