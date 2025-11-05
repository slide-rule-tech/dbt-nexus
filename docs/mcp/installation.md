---
title: Installation
tags: [mcp, installation, setup]
summary: Installation and setup guide for the Nexus MCP server
---

# Installation Guide

## Prerequisites

- Node.js 18+ installed
- dbt project with nexus package installed
- dbt models compiled (run `dbt compile` or `dbt run`)
- Access to BigQuery or Snowflake data warehouse

## Installation Steps

### 1. Install Dependencies

Navigate to the mcp-nexus directory:

```bash
cd dbt_packages/nexus/mcp-nexus
npm install
```

### 2. Build the Project

```bash
npm run build
```

This compiles TypeScript to JavaScript in the `dist/` directory.

### 3. Configure MCP in Cursor

Create or edit `.cursor/mcp.json` in your dbt project root:

```json
{
  "mcpServers": {
    "nexus": {
      "command": "node",
      "args": [
        "/absolute/path/to/dbt_packages/nexus/mcp-nexus/dist/index.js",
        "--project-dir",
        "."
      ],
      "env": {
        "DBT_PROFILES_DIR": "/Users/yourusername/.dbt"
      }
    }
  }
}
```

**Important**: Replace `/absolute/path/to/` with the actual absolute path to your project.

### 4. Verify dbt Configuration

Ensure your dbt project is properly configured:

- `dbt_project.yml` exists in your project root
- `~/.dbt/profiles.yml` (or `DBT_PROFILES_DIR`) contains your profile
- `target/manifest.json` exists (run `dbt compile` if needed)

### 5. Test the Connection

Restart Cursor and try using one of the nexus tools. The server will:
- Auto-detect your dbt project
- Load your profile and target
- Connect to your warehouse
- Discover nexus models

## Environment Variables

- `DBT_PROFILES_DIR`: Override the default dbt profiles directory (`~/.dbt`)

## Troubleshooting

### "dbt_project.yml not found"
- Ensure you're running from a dbt project directory
- Or specify `--project-dir` with the correct path

### "manifest.json not found"
- Run `dbt compile` or `dbt run` to generate the manifest
- Ensure the `target/` directory exists

### "Profile not found"
- Check that your profile exists in `~/.dbt/profiles.yml`
- Verify the profile name matches your `dbt_project.yml`
- Set `DBT_PROFILES_DIR` if using a custom location

### "Warehouse connection failed"
- Verify your dbt target credentials are correct
- Check network connectivity to BigQuery/Snowflake
- Ensure authentication credentials are valid

See [Troubleshooting Guide](troubleshooting.md) for more help.

