---
title: Configuration Guide
tags: [configuration, setup, variables, sources]
summary:
  Complete guide to configuring dbt-nexus variables, sources, and model behavior
---

# Configuration Guide

This guide covers all configuration options for dbt-nexus, from basic setup to
advanced customization.

## Overview

dbt-nexus uses a variable-driven architecture that allows you to:

- Define which data sources to process
- Control identity resolution behavior
- Customize model materialization
- Configure performance optimizations
- Set up cross-database compatibility

## Core Configuration Variables

### Required Variables

#### Sources Configuration

The `sources` variable is the heart of dbt-nexus configuration. It tells the
package which data sources to process and what entity types each source
provides.

```yaml
# dbt_project.yml
vars:
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

    - name: "stripe"
      events: true
      persons: true
      groups: true
      memberships: false

    - name: "manual"
      events: true
      persons: true
      groups: true
      memberships: true
```

**Source Properties:**

| Property      | Type    | Required | Description                                        |
| ------------- | ------- | -------- | -------------------------------------------------- |
| `name`        | string  | ✅       | Unique identifier for the source system            |
| `events`      | boolean | ✅       | Whether source provides event data                 |
| `persons`     | boolean | ✅       | Whether source provides person data                |
| `groups`      | boolean | ✅       | Whether source provides group/organization data    |
| `memberships` | boolean | ✅       | Whether source provides person-group relationships |

### Optional Variables

#### Identity Resolution Configuration

```yaml
vars:
  # Maximum recursion depth for identity resolution
  nexus_max_recursion: 5 # Default: 5

  # Identity resolution window (for performance optimization)
  id_resolution_window_days: 30 # Default: no limit
```

#### Development Overrides

```yaml
vars:
  # Force full refresh in development environment
  override_incremental: false # Default: false

  # Enable only in development environment
  dev_only_override: true # Default: true
```

#### Performance Configuration

```yaml
vars:
  # Incremental strategy for supported warehouses
  incremental_strategy: "merge" # Options: merge, insert_overwrite, delete+insert

  # Batch size for large operations
  batch_size: 10000 # Default: varies by operation
```

## Model Configuration

### Materialization Strategy

Configure how different model groups are materialized:

```yaml
# dbt_project.yml
models:
  nexus:
    # Default materialization for all nexus models
    +materialized: table

    # Event log models - use incremental for large volumes
    event_log:
      +materialized: incremental
      +unique_key: id
      +incremental_strategy: merge

    # Identity resolution models - tables for performance
    identity_resolution:
      +materialized: table

    # Final tables - tables with specific schema
    final_tables:
      +materialized: table
      +schema: marts
```

### Schema Organization

Organize models into logical schemas:

```yaml
models:
  nexus:
    event_log:
      +schema: event_log
    identity_resolution:
      +schema: identity_resolution
    final_tables:
      +schema: marts
    # Optional: Raw/staging layers
    staging:
      +schema: staging
```

### Tags and Selection

Use tags for model selection and management:

```yaml
models:
  nexus:
    event_log:
      +tags: ["nexus", "event_log", "incremental"]
    identity_resolution:
      +tags: ["nexus", "identity_resolution", "daily"]
    final_tables:
      +tags: ["nexus", "marts", "production"]
```

## Source-Specific Configuration

### Naming Conventions

dbt-nexus expects source models to follow specific naming conventions:

```
models/sources/{source_name}/
├── {source_name}_events.sql
├── {source_name}_person_identifiers.sql
├── {source_name}_person_traits.sql
├── {source_name}_group_identifiers.sql
├── {source_name}_group_traits.sql
└── {source_name}_membership_identifiers.sql
```

### Custom Source Variables

You can define source-specific variables:

```yaml
vars:
  # Source-specific configuration
  shopify_partner:
    app_id_filter: ["12345", "67890"] # Only process specific apps
    event_types: ["app_installed", "charge_created"] # Filter event types

  gmail:
    email_domains: ["company.com", "subsidiary.com"] # Filter domains
    max_attachment_size: 10485760 # 10MB limit
```

## Advanced Configuration

### Cross-Database Compatibility

dbt-nexus is fully tested and optimized for both **Snowflake** and **BigQuery**.
Configure database-specific behavior:

```yaml
# BigQuery-specific configuration
models:
  nexus:
    +materialized: table
    +cluster_by: ["occurred_at", "source"]
    +partition_by: {
      "field": "occurred_at",
      "data_type": "timestamp",
      "granularity": "day"
    }

# Snowflake-specific configuration
models:
  nexus:
    +materialized: table
    +cluster_by: ["occurred_at", "source"]
    +transient: false
```

### Incremental Configuration

Fine-tune incremental behavior:

```yaml
models:
  nexus:
    event_log:
      events:
        +materialized: incremental
        +unique_key: id
        +incremental_strategy: merge
        +on_schema_change: fail

      person_identifiers:
        +materialized: incremental
        +unique_key: id
        +incremental_strategy: merge
        +on_schema_change: sync_all_columns
```

### Performance Optimizations

```yaml
vars:
  # Performance tuning
  nexus_performance:
    # Use smaller batches for identity resolution
    identity_batch_size: 5000

    # Parallel processing for large sources
    enable_parallel_processing: true
    max_parallel_jobs: 4

    # Memory optimization
    use_temp_tables: true
    optimize_joins: true
```

## Environment-Specific Configuration

### Development Environment

```yaml
# profiles.yml or dbt_project.yml
vars:
  # Development-specific overrides
  override_incremental: true # Force full refresh
  nexus_max_recursion: 3 # Faster processing

  # Use smaller datasets in dev
  dev_data_limit: 10000 # Limit rows processed

  # Simplified materialization
models:
  nexus:
    +materialized: view # Faster development cycles
```

### Production Environment

```yaml
vars:
  # Production optimizations
  override_incremental: false
  nexus_max_recursion: 10 # More thorough resolution

  # Performance settings
  batch_size: 100000
  enable_parallel_processing: true

models:
  nexus:
    +materialized: table # Optimized for queries
    +cluster_by: ["person_id", "group_id"]
```

### Testing Environment

```yaml
vars:
  # Test-specific configuration
  use_test_data: true
  test_data_days: 7 # Only recent data

models:
  nexus:
    +materialized: table
    +post-hook: "ANALYZE TABLE {{ this }}" # Update statistics
```

## Validation and Testing

### Configuration Validation

Validate your configuration with these queries:

```sql
-- Check source configuration
{{ nexus.validate_sources() }}

-- Check required models exist
{{ nexus.validate_source_models() }}

-- Verify identity resolution settings
{{ nexus.validate_identity_config() }}
```

### Model Testing

Configure tests for data quality:

```yaml
# models/schema.yml
models:
  - name: nexus_persons
    tests:
      - unique:
          column_name: person_id
      - not_null:
          column_name: person_id
    columns:
      - name: email
        tests:
          - not_null
          - email_format

  - name: nexus_events
    tests:
      - unique:
          column_name: id
      - not_null:
          column_name: occurred_at
      - relationships:
          to: source('sources', 'all_events')
          field: id
```

## Configuration Examples

### Minimal Configuration

Basic setup for a single source:

```yaml
# dbt_project.yml
vars:
  sources:
    - name: "manual"
      events: true
      persons: true
      groups: true
      memberships: false

models:
  nexus:
    +materialized: table
    +schema: nexus
```

### Multi-Source Configuration

Complex setup with multiple data sources:

```yaml
vars:
  # Multiple sources with different capabilities
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

    - name: "salesforce"
      events: true
      persons: true
      groups: true
      memberships: true

    - name: "segment"
      events: true
      persons: true
      groups: false
      memberships: false

  # Optimize for multiple sources
  nexus_max_recursion: 8
  id_resolution_window_days: 90

models:
  nexus:
    event_log:
      +materialized: incremental
      +unique_key: id
    identity_resolution:
      +materialized: table
      +cluster_by: ["identifier_type", "identifier_value"]
    final_tables:
      +materialized: table
      +schema: crm
```

### High-Performance Configuration

Optimized for large-scale processing:

```yaml
vars:
  sources: [...] # Your sources

  # Performance optimizations
  nexus_max_recursion: 15
  incremental_strategy: "insert_overwrite"
  batch_size: 100000

models:
  nexus:
    +materialized: incremental
    +unique_key: id
    +cluster_by: ["occurred_at"]
    +partition_by: { "field": "occurred_at", "data_type": "timestamp" }

    final_tables:
      +materialized: table
      +cluster_by: ["person_id", "group_id"]
```

## Troubleshooting Configuration

### Common Issues

**1. Missing Models Error**

```
Model 'source_name_events' not found
```

**Solution**: Ensure source models exist with correct naming convention

**2. Variable Not Found**

```
'sources' is undefined
```

**Solution**: Add sources configuration to `dbt_project.yml`

**3. Recursion Errors**

```
Maximum recursion depth exceeded
```

**Solution**: Reduce `nexus_max_recursion` or optimize data relationships

**4. Performance Issues**

```
Query timeout or excessive memory usage
```

**Solution**: Use incremental materialization and reduce batch sizes

### Validation Commands

```bash
# Validate configuration
dbt run-operation nexus_validate_config

# Check model dependencies
dbt list --models nexus --output json

# Test configuration changes
dbt run --models nexus --vars '{"override_incremental": true}'
```

## Next Steps

After configuring dbt-nexus:

1. [Test your configuration](../how-to/testing.md)
2. [Build your first models](quick-start.md)
3. [Set up monitoring](../how-to/monitoring.md)
4. [Optimize performance](../explanations/performance.md)
