---
title: Troubleshooting
tags: [mcp, troubleshooting, debugging]
summary: Common issues and solutions for the Nexus MCP server
---

# Troubleshooting

Common issues and solutions when using the Nexus MCP server.

## Initialization Issues

### "dbt_project.yml not found"

**Problem**: The server cannot find your dbt project.

**Solutions**:
- Ensure you're running from a dbt project directory
- Check that `dbt_project.yml` exists in the current directory
- Specify `--project-dir` with the absolute path to your project
- Verify the path in `.cursor/mcp.json` is correct

### "manifest.json not found"

**Problem**: The server cannot find the dbt manifest.

**Solutions**:
- Run `dbt compile` or `dbt run` to generate the manifest
- Check that the `target/` directory exists
- Verify the manifest path: `target/manifest.json`
- Ensure you have run dbt at least once in the project

### "Profile not found"

**Problem**: The server cannot find or load your dbt profile.

**Solutions**:
- Verify your profile exists in `~/.dbt/profiles.yml`
- Check that the profile name in `dbt_project.yml` matches your profile
- Set `DBT_PROFILES_DIR` environment variable if using a custom location
- Verify the profile has the correct target configured

### "Target not found in profile"

**Problem**: The specified target doesn't exist in your profile.

**Solutions**:
- Check available targets in `~/.dbt/profiles.yml`
- Verify the target name in `dbt_project.yml`
- Ensure the target is configured with correct credentials

## Connection Issues

### "BigQuery connection failed"

**Problem**: Cannot connect to BigQuery.

**Solutions**:
- Verify BigQuery credentials in your dbt target
- Check that service account key file path is correct
- Ensure service account has necessary permissions
- Verify project ID is correct
- Check network connectivity to BigQuery

### "Snowflake connection failed"

**Problem**: Cannot connect to Snowflake.

**Solutions**:
- Verify Snowflake credentials in your dbt target
- Check account, user, warehouse, database, and schema
- Ensure password or private key is correct
- Verify network connectivity to Snowflake
- Check that user has necessary permissions

## Model Discovery Issues

### "Required nexus models not found"

**Problem**: The server cannot find nexus models in the manifest.

**Solutions**:
- Ensure nexus package is installed: `dbt deps`
- Verify nexus models are built: `dbt run --select package:nexus`
- Check that models exist in `target/manifest.json`
- Verify model names match expected patterns:
  - `nexus_entities`
  - `nexus_relationships`
  - `nexus_events`
  - `nexus_entity_participants`

### "Schema not found"

**Problem**: Cannot determine schema from models.

**Solutions**:
- Verify models are built in the expected schema
- Check dbt target schema configuration
- Ensure schema names are consistent

## Query Issues

### "Query execution failed"

**Problem**: SQL query fails to execute.

**Solutions**:
- Check the generated SQL in the response (`query` field)
- Verify table names and schema are correct
- Check column names match your schema
- Ensure you have read permissions on tables
- Review warehouse error messages

### "No results returned"

**Problem**: Query executes but returns no data.

**Solutions**:
- Verify filters are correct
- Check that data exists in tables
- Review query conditions
- Try removing filters to see if data exists
- Check date/time formats in filters

### "Invalid filter operator"

**Problem**: Filter operator is not supported.

**Solutions**:
- Use supported operators: `=`, `!=`, `>`, `<`, `>=`, `<=`, `LIKE`, `IN`, `IS NULL`, `IS NOT NULL`
- For `IN` operator, ensure value is an array
- For `IS NULL`/`IS NOT NULL`, don't provide a value

## Performance Issues

### "Query is slow"

**Problem**: Queries take too long to execute.

**Solutions**:
- Add filters to limit results
- Use `limit` to restrict result size
- Check for missing indexes on filtered columns
- Review query execution plan
- Consider adding aggregations only when needed

### "Too many results"

**Problem**: Query returns too much data.

**Solutions**:
- Always specify a `limit` parameter
- Use filters to narrow results
- Use pagination with `offset` for large result sets
- Consider using more specific queries

## Debugging

### Enable Verbose Logging

The server logs to stderr. Check console output for:
- Connection status
- Query execution times
- Generated SQL queries
- Error messages

### Inspect Generated SQL

All tool responses include a `query` field with the generated SQL. Use this to:
- Verify query logic
- Debug filter conditions
- Check table/column names
- Test queries directly in your warehouse

### Test Connection Manually

Test your dbt connection:
```bash
dbt debug
```

This verifies:
- Profile configuration
- Warehouse connection
- Permissions

### Verify Models

Check that nexus models exist:
```bash
dbt list --select package:nexus
```

List all models:
```bash
dbt list
```

## Getting Help

If issues persist:

1. **Check logs**: Review console output for detailed error messages
2. **Verify configuration**: Ensure all paths and credentials are correct
3. **Test manually**: Try running queries directly in your warehouse
4. **Check documentation**: Review [tool reference](tools.md) and [examples](examples.md)
5. **Report issues**: Include error messages, SQL queries, and configuration details

## Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| "dbt_project.yml not found" | Wrong directory | Use `--project-dir` or run from project root |
| "manifest.json not found" | Models not compiled | Run `dbt compile` |
| "Profile not found" | Missing profile | Check `~/.dbt/profiles.yml` |
| "Connection failed" | Invalid credentials | Verify warehouse credentials |
| "Model not found" | Models not built | Run `dbt run --select package:nexus` |
| "Query failed" | SQL error | Check generated SQL in response |

