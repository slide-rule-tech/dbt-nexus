---
title: Installation Guide
tags: [installation, setup, configuration]
summary: Step-by-step guide to install and configure dbt-nexus
---

# Installation Guide

This guide walks you through installing and configuring the dbt-nexus package in
your dbt project.

## Prerequisites

Before installing dbt-nexus, ensure you have:

- **dbt version >= 1.0.0** (Update if necessary based on features used)
- A supported data warehouse:
  - Snowflake ✅
  - BigQuery ✅
  - Postgres ✅
  - Redshift ✅
  - Databricks ✅
- Required dbt packages:
  - `dbt-utils` (automatically installed)
  - `dbt-date` (automatically installed)

## Installation Methods

### Method 1: Git Repository (Recommended)

For public repositories or Git-based installations:

```yaml
# packages.yml
packages:
  - git: "https://github.com/sliderule/dbt-nexus.git"
    version: 0.1.0 # Use specific version or branch
```

### Method 2: Local Package

For local development or private repositories:

```yaml
# packages.yml
packages:
  - local: path/to/dbt-nexus # e.g., external_libs/dbt-nexus
```

### Method 3: dbt Hub (Future)

Once published to dbt Hub:

```yaml
# packages.yml
packages:
  - package: sliderule/nexus
    version: [">=0.1.0", "<1.0.0"]
```

## Installation Steps

1. **Add to packages.yml**

   Add the package definition to your `packages.yml` file using one of the
   methods above.

2. **Install dependencies**

   ```bash
   dbt deps
   ```

3. **Verify installation**

   ```bash
   dbt list --models nexus
   ```

   You should see all dbt-nexus models listed.

## Package Configuration

### Required Configuration

Add the following to your `dbt_project.yml`:

```yaml
vars:
  # Required: Define your data sources
  sources:
    - name: "shopify_partner"
      events: true
      persons: false
      groups: true
      memberships: false

    - name: "gmail"
      events: true
      persons: true
      groups: false
      memberships: false

    - name: "manual"
      events: true
      persons: true
      groups: true
      memberships: true

  # Optional: Control recursion depth for identity resolution
  nexus_max_recursion: 5

  # Optional: Override incremental behavior in development
  override_incremental: false # Set to true for full refresh in dev
```

### Source Configuration Details

Each source in the `sources` list must specify which entity types it provides:

- **`events`**: Whether this source provides event data
- **`persons`**: Whether this source provides person identifiers/traits
- **`groups`**: Whether this source provides group/organization data
- **`memberships`**: Whether this source provides person-group relationships

### Model Materialization

Configure how nexus models are materialized:

```yaml
# In your dbt_project.yml
models:
  nexus:
    +materialized: table # Default materialization
    event_log:
      +materialized: incremental
      +unique_key: id
    identity_resolution:
      +materialized: table
    final_tables:
      +materialized: table
      +schema: marts # Put final tables in marts schema
```

### Schema Configuration

Organize nexus models into schemas:

```yaml
models:
  nexus:
    event_log:
      +schema: event_log
    identity_resolution:
      +schema: identity_resolution
    final_tables:
      +schema: marts
```

## Source Adapter Implementation

After configuring the package, you need to create source adapter models that
transform your raw data into the nexus format.

### Required Source Models

For each source defined in your configuration, create models following this
naming convention:

```
models/sources/{source_name}/
├── {source_name}_events.sql              # If events: true
├── {source_name}_person_identifiers.sql  # If persons: true
├── {source_name}_person_traits.sql       # If persons: true
├── {source_name}_group_identifiers.sql   # If groups: true
├── {source_name}_group_traits.sql        # If groups: true
└── {source_name}_membership_identifiers.sql  # If memberships: true
```

### Example: Shopify Partner Source

**File: `models/sources/shopify_partner/shopify_partner_events.sql`**

```sql
{{ config(materialized='table') }}

WITH source_data AS (
    SELECT *
    FROM {{ source('shopify_partner', 'app_events') }}
    {% if is_incremental() %}
    WHERE synced_at > (SELECT MAX(synced_at) FROM {{ this }})
    {% endif %}
)

SELECT
    id,
    occurred_at,
    event_name,
    event_description,
    value,
    value_unit,
    event_type,
    'shopify_partner' as source,
    {{ current_timestamp() }} as _ingested_at,
    synced_at
FROM source_data
```

**File: `models/sources/shopify_partner/shopify_partner_group_identifiers.sql`**

```sql
{{ config(materialized='table') }}

WITH source_data AS (
    SELECT *
    FROM {{ ref('shopify_partner_events') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['id', 'shop_domain']) }} as id,
    id as event_id,
    {{ dbt_utils.generate_surrogate_key(['id']) }} as row_id,
    'domain' as identifier_type,
    shop_domain as identifier_value,
    'shopify_partner' as source,
    occurred_at,
    _ingested_at
FROM source_data
WHERE shop_domain IS NOT NULL

UNION ALL

SELECT
    {{ dbt_utils.generate_surrogate_key(['id', 'shop_id']) }} as id,
    id as event_id,
    {{ dbt_utils.generate_surrogate_key(['id']) }} as row_id,
    'shop_id' as identifier_type,
    shop_id as identifier_value,
    'shopify_partner' as source,
    occurred_at,
    _ingested_at
FROM source_data
WHERE shop_id IS NOT NULL
```

### Source Model Requirements

Each source model must include these required fields:

#### Events Models

- `id` - Unique event identifier
- `occurred_at` - Event timestamp
- `event_name` - Specific event name
- `event_type` - Event category
- `source` - Source system name
- `_ingested_at` - Processing timestamp

#### Identifier Models

- `id` - Unique identifier record
- `event_id` - Reference to source event
- `row_id` - Groups related identifiers
- `identifier_type` - Type of identifier
- `identifier_value` - Actual identifier value
- `source` - Source system
- `occurred_at` - When collected
- `_ingested_at` - When processed

#### Trait Models

- `id` - Unique trait record
- `event_id` - Reference to source event
- `row_id` - Groups related traits
- `trait_name` - Trait name
- `trait_value` - Trait value
- `source` - Source system
- `occurred_at` - When collected
- `_ingested_at` - When processed

## Initial Build

After configuration and source model creation:

1. **Build source models first**

   ```bash
   dbt run --models sources
   ```

2. **Build nexus models**

   ```bash
   dbt run --models nexus
   ```

3. **Run tests**
   ```bash
   dbt test --models nexus
   ```

## Verification

### Check Final Tables

Verify that your final tables contain expected data:

```sql
-- Check persons table
SELECT COUNT(*) as person_count FROM {{ ref('nexus_persons') }};

-- Check groups table
SELECT COUNT(*) as group_count FROM {{ ref('nexus_groups') }};

-- Check events table
SELECT COUNT(*) as event_count FROM {{ ref('nexus_events') }};

-- Verify identity resolution worked
SELECT
    COUNT(DISTINCT person_id) as unique_persons,
    COUNT(*) as total_identifiers
FROM {{ ref('nexus_resolved_person_identifiers') }};
```

### Monitor Identity Resolution

Check identity resolution effectiveness:

```sql
-- Identity resolution summary
WITH person_summary AS (
    SELECT
        person_id,
        COUNT(*) as identifier_count,
        COUNT(DISTINCT identifier_type) as identifier_types
    FROM {{ ref('nexus_resolved_person_identifiers') }}
    GROUP BY person_id
)
SELECT
    AVG(identifier_count) as avg_identifiers_per_person,
    AVG(identifier_types) as avg_identifier_types_per_person,
    COUNT(*) as total_resolved_persons
FROM person_summary;
```

## Troubleshooting

### Common Issues

**1. Missing source models**

```
Error: Model 'shopify_partner_events' not found
```

**Solution**: Ensure all required source models exist with correct naming

**2. Recursion limit exceeded**

```
Error: Maximum recursion depth exceeded
```

**Solution**: Reduce `nexus_max_recursion` value or optimize identifier
relationships

**3. Schema conflicts**

```
Error: Relation already exists
```

**Solution**: Use different schema configurations or drop existing tables

**4. Performance issues**

```
Error: Query timeout
```

**Solution**: Switch to incremental materialization for large models

### Getting Help

If you encounter issues:

1. Check the [Troubleshooting Guide](../ai-context/troubleshooting.md)
2. Review [Common Tasks](../ai-context/common-tasks.md)
3. Consult [package documentation](https://sliderule.github.io/dbt-nexus)
4. Open an issue on [GitHub](https://github.com/sliderule/dbt-nexus/issues)

## Next Steps

After successful installation:

1. [Configure your first source](configuration.md)
2. [Explore identity resolution](../explanations/identity-resolution.md)
3. [Build operational applications](../explanations/use-cases.md)
