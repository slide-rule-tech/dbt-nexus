---
title: Troubleshooting Guide
tags: [ai-context, troubleshooting, debugging, common-issues]
summary:
  Common issues, solutions, and debugging strategies for dbt-nexus
  implementation.
---

# Troubleshooting Guide

## Installation Issues

### Package Not Found

**Problem**: `Package 'nexus' not found`

**Solutions**:

1. Verify `packages.yml` configuration:
   ```yaml
   packages:
     - git: "https://github.com/sliderule-analytics/dbt-nexus.git"
       version: main
   ```
2. Run `dbt deps` to install dependencies
3. Check network connectivity to GitHub

### Submodule Issues

**Problem**: Submodule not updating or showing as modified

**Solutions**:

1. Update submodule:
   ```bash
   git submodule update --remote dbt-nexus
   ```
2. Initialize if needed:
   ```bash
   git submodule update --init --recursive
   ```
3. Check submodule status:
   ```bash
   git submodule status
   ```

## Configuration Issues

### Models Not Building

**Problem**: `Model 'nexus_persons' not found`

**Solutions**:

1. Check `sources` variable configuration in `dbt_project.yml`
2. Verify source model naming conventions
3. Ensure source models exist and compile successfully
4. Run `dbt list --select package:nexus` to see available models

### Schema Configuration Errors

**Problem**: `Multiple 'models:' keys found`

**Solutions**:

1. Ensure only ONE `models:` section in `dbt_project.yml`
2. Use correct package name (`nexus`, not `dbt-nexus`)
3. Check YAML indentation and structure

### Recursion Errors

**Problem**: `Recursive CTE exceeded maximum recursion depth`

**Solutions**:

1. Adjust `nexus_max_recursion` value:
   ```yaml
   vars:
     nexus_max_recursion: 3 # Reduce from default 5
   ```
2. Check data quality for circular references
3. Review identity resolution logic

## Data Quality Issues

### Missing Identities

**Problem**: Persons not resolving across sources

**Solutions**:

1. Verify source model schema compliance
2. Check identifier column names and types
3. Ensure proper data types (strings for identifiers)
4. Review data quality in source systems

### Duplicate Entities

**Problem**: Same person appearing multiple times in final tables

**Solutions**:

1. Check identity resolution logic
2. Verify edge creation in `nexus_person_identifiers_edges`
3. Review recursive CTE behavior
4. Test with smaller dataset to isolate issues

### State Timeline Gaps

**Problem**: Missing or incorrect state transitions

**Solutions**:

1. Verify `occurred_at` timestamps in events
2. Check state model logic for proper timeline handling
3. Ensure state models are added to `nexus_states` union
4. Review derived state calculations

## Performance Issues

### Slow Identity Resolution

**Problem**: Identity resolution models taking too long to run

**Solutions**:

1. Reduce `nexus_max_recursion` value
2. Add incremental materialization:
   ```yaml
   models:
     nexus:
       nexus-models:
         identity-resolution:
           +materialized: incremental
   ```
3. Consider partitioning for large datasets
4. Review data volume and complexity

### Memory Issues

**Problem**: Out of memory errors during model execution

**Solutions**:

1. Reduce batch sizes in incremental models
2. Add partitioning to large tables
3. Optimize recursive CTE depth
4. Consider materializing intermediate models

### Incremental Model Issues

**Problem**: Incremental models not updating correctly

**Solutions**:

1. Check `_ingested_at` values in source data
2. Verify incremental strategy configuration
3. Review watermark logic in models
4. Consider full refresh if logic changes

## Demo Data Issues

### Demo Data Not Building

**Problem**: Demo models failing to compile or run

**Solutions**:

1. Ensure you haven't overridden package `vars` configuration
2. Check BigQuery permissions for demo schema creation
3. Verify service account has proper access
4. Run from package directory:
   ```bash
   cd dbt_packages/nexus
   dbt build
   ```

### Missing Demo Models

**Problem**: Expected demo models not appearing

**Solutions**:

1. Run `dbt list --select package:nexus` to see available models
2. Check if demo data configuration is active
3. Verify package installation with `dbt deps`
4. Review package version and compatibility

## Database-Specific Issues

### BigQuery Issues

**Problem**: BigQuery-specific errors or performance issues

**Solutions**:

1. Check service account permissions
2. Verify project ID and dataset configuration
3. Review BigQuery-specific optimizations in models
4. Consider partitioning and clustering strategies

### Snowflake Issues

**Problem**: Snowflake-specific errors or performance issues

**Solutions**:

1. Verify warehouse configuration and sizing
2. Check Snowflake-specific optimizations
3. Review recursive CTE behavior in Snowflake
4. Consider clustering keys for large tables

### PostgreSQL Issues

**Problem**: PostgreSQL compatibility issues

**Solutions**:

1. Check PostgreSQL version compatibility
2. Verify recursive CTE support
3. Review data type mappings
4. Consider performance tuning for PostgreSQL

## Common Error Messages

### "Column 'X' not found"

**Cause**: Source model schema mismatch **Solution**: Verify column names and
types in source models

### "Recursive CTE depth exceeded"

**Cause**: Too many identity resolution iterations **Solution**: Reduce
`nexus_max_recursion` value

### "Model 'nexus_X' not found"

**Cause**: Package not installed or configured **Solution**: Run `dbt deps` and
check `packages.yml`

### "Multiple models with name 'X'"

**Cause**: Naming conflicts between project and package models **Solution**: Use
unique model names or proper namespacing

## Debugging Strategies

### Enable Debug Logging

```bash
dbt run --debug
dbt test --debug
```

### Check Model Lineage

```bash
dbt docs generate
dbt docs serve
```

### Verify Data Quality

```sql
-- Check for null identifiers
SELECT COUNT(*) FROM nexus_person_identifiers
WHERE identifier_value IS NULL;

-- Check for duplicate events
SELECT event_id, COUNT(*) FROM nexus_events
GROUP BY event_id HAVING COUNT(*) > 1;
```

### Test with Minimal Dataset

```bash
# Run specific source only
dbt run --select source:your_source
dbt run --select package:nexus --models tag:identity-resolution
```

## Getting Help

### Documentation Resources

- [Complete Documentation](https://sliderule-analytics.github.io/dbt-nexus)
- [GitHub Repository](https://github.com/sliderule-analytics/dbt-nexus)
- [Model Reference](../reference/models/)
- [Macro Reference](../reference/macros/)

### Community Support

- [dbt Community Slack](https://community.getdbt.com/)
- [GitHub Issues](https://github.com/sliderule-analytics/dbt-nexus/issues)
- [dbt Discourse](https://discourse.getdbt.com/)

### Professional Support

- [SlideRule Analytics](https://www.slideruleanalytics.com/)
- Custom implementation and consulting services
