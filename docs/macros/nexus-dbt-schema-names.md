---
title: Schema Naming Configuration
tags: [reference, schema, configuration, nexus]
summary:
  Complete guide to schema naming behavior for nexus models and template sources
---

# Schema Naming Configuration

The nexus package uses a custom `generate_schema_name` macro to provide flexible
and consistent schema naming across different data warehouses and environments.

## Overview

The schema naming system distinguishes between different types of models:

- **Core nexus models**: Use `nexus_{{ target.name }}` schema naming
- **Template source models**: Use default dbt schema naming (same as client
  models)
- **Client models**: Use standard dbt schema naming

## Default Behavior

### Core Nexus Models

Core nexus models (in `nexus-models/` directory) build into schemas based on the
target environment:

- **Dev target**: `nexus_dev`
- **Prod target**: `nexus_prod`
- **Other targets**: `nexus_{{ target.name }}`

### Template Source Models

Template source models (in `sources/` directory) use the default dbt schema
naming:

- Uses the `schema` value from your dbt profile configuration
- Same behavior as your client models
- Example: `development` schema for dev target

### Client Models

Your project's models use standard dbt schema naming:

- Uses the `schema` value from your dbt profile configuration
- Follows standard dbt conventions

## Custom Schema Override

You can override the default nexus schema naming using variables:

### Configuration in dbt_project.yml

```yaml
# dbt_project.yml
vars:
  nexus_schema_dev: "my_custom_dev_schema"
  nexus_schema_prod: "my_custom_prod_schema"
```

### Command Line Override

```bash
# Override dev schema
dbt run --vars '{"nexus_schema_dev": "custom_dev_schema"}'

# Override prod schema
dbt run --vars '{"nexus_schema_prod": "custom_prod_schema"}'

# Override both
dbt run --vars '{"nexus_schema_dev": "custom_dev", "nexus_schema_prod": "custom_prod"}'
```

## Cross-Warehouse Compatibility

The schema naming works consistently across all supported data warehouses:

### BigQuery

- **Project**: Uses `target.project` from profile
- **Dataset**: Uses the generated schema name
- **Table**: Uses the model name
- **Format**: `project.dataset.table`

### Snowflake

- **Database**: Uses `target.database` from profile
- **Schema**: Uses the generated schema name
- **Table**: Uses the model name
- **Format**: `database.schema.table`

### PostgreSQL

- **Database**: Uses `target.database` from profile
- **Schema**: Uses the generated schema name
- **Table**: Uses the model name
- **Format**: `database.schema.table`

## Schema Naming Priority

The macro follows this priority order for nexus models:

1. **Custom variables** (`nexus_schema_dev` or `nexus_schema_prod`)
2. **Default nexus naming** (`nexus_{{ target.name }}`)
3. **Custom schema name** (if specified in model config)

For non-nexus models, it uses standard dbt behavior:

1. **Custom schema name** (if specified in model config)
2. **Default schema** (from profile configuration)

## Examples

### Default Configuration

```yaml
# profiles.yml
slide_rule_tech:
  outputs:
    dev:
      schema: development
    prod:
      schema: production
```

**Result:**

- Core nexus models: `nexus_dev`, `nexus_prod`
- Template sources: `development`, `production`
- Client models: `development`, `production`

### Custom Schema Override

```yaml
# dbt_project.yml
vars:
  nexus_schema_dev: "analytics_dev"
  nexus_schema_prod: "analytics_prod"
```

**Result:**

- Core nexus models: `analytics_dev`, `analytics_prod`
- Template sources: `development`, `production` (unchanged)
- Client models: `development`, `production` (unchanged)

### Mixed Configuration

```yaml
# dbt_project.yml
vars:
  nexus_schema_dev: "analytics_dev"
  # nexus_schema_prod not set
```

**Result:**

- Core nexus models: `analytics_dev` (dev), `nexus_prod` (prod)
- Template sources: `development`, `production`
- Client models: `development`, `production`

## Troubleshooting

### Schema Not Updating

If schema names aren't updating as expected:

1. **Check macro location**: Ensure `generate_schema_name.sql` is in your
   project's `macros/` directory
2. **Verify variable syntax**: Use correct YAML syntax for variables
3. **Check target name**: Ensure your target name matches the variable name
   (`nexus_schema_dev` for dev target)
4. **Clear dbt cache**: Run `dbt clean` and `dbt deps` to refresh

### Cross-Warehouse Issues

If schemas aren't working across different warehouses:

1. **Check profile configuration**: Ensure database/project names are correct
2. **Verify permissions**: Ensure the service account/user has access to create
   schemas
3. **Test with simple models**: Start with basic models to isolate issues

### Template Sources Using Wrong Schema

If template sources are using nexus schema instead of default:

1. **Check file path**: Ensure models are in `sources/` directory
2. **Verify macro logic**: The macro checks for `'sources/'` in the file path
3. **Update macro**: Ensure the latest version of the macro is being used

## Migration Guide

### From Previous Versions

If you're upgrading from a version without custom schema naming:

1. **No changes needed**: Default behavior remains the same
2. **Optional customization**: Add variables to customize schema names
3. **Test thoroughly**: Verify schema names in your target environment

### Adding Custom Schema Names

To add custom schema names to an existing project:

1. **Add variables** to your `dbt_project.yml`
2. **Test in dev** environment first
3. **Update references** if any models reference specific schema names
4. **Deploy to prod** once verified

## Best Practices

### Schema Naming Conventions

- **Use descriptive names**: Make schema names clear and meaningful
- **Include environment**: Always include environment in schema names
- **Be consistent**: Use the same naming pattern across all environments
- **Avoid conflicts**: Ensure schema names don't conflict with existing schemas

### Environment Management

- **Separate dev/prod**: Use different schema names for different environments
- **Use variables**: Leverage dbt variables for environment-specific
  configuration
- **Document changes**: Keep track of schema naming decisions and changes

### Performance Considerations

- **Schema creation**: Be aware that creating new schemas may require additional
  permissions
- **Cross-schema queries**: Consider performance implications of queries across
  schemas
- **Indexing**: Ensure proper indexing for cross-schema references
