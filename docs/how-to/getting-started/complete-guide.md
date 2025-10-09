---
title: Complete Getting Started Guide
tags: [getting-started, installation, configuration, setup, dbt-nexus]
summary:
  Complete step-by-step guide to get up and running with dbt-nexus from project
  initialization to production deployment
---

# Complete Getting Started Guide

Welcome to the comprehensive dbt-nexus getting started guide! This guide
provides everything you need to go from zero to a fully functional dbt-nexus
implementation.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initialize a New dbt Project](#initialize-a-new-dbt-project)
3. [Install and Configure dbt-nexus](#install-and-configure-dbt-nexus)
4. [Package Configuration](#package-configuration)
5. [Demo Data Setup](#demo-data-setup)
6. [Local Development Setup](#local-development-setup)
7. [Next Steps](#next-steps)

---

## Prerequisites

Before you begin, ensure you have the following installed:

- **Python 3.7+** - Required for dbt and Python dependencies
- **Git** - For version control
- **Data Warehouse Access** - BigQuery, Snowflake, PostgreSQL, Redshift, or
  Databricks
- **Basic familiarity** with dbt concepts
- **Data sources configured** (optional - can use demo data initially)

### Supported Data Warehouses

dbt-nexus is fully tested and optimized for:

- **Snowflake** ✅ (Primary support)
- **BigQuery** ✅ (Primary support)
- **PostgreSQL** ✅
- **Redshift** ✅
- **Databricks** ✅

---

## Initialize a New dbt Project

### Step 1: Set Up Your Data Warehouse

#### BigQuery Setup

1. **Create a BigQuery project** in Google Cloud Platform

   - Choose a descriptive project ID (e.g., `your-company-analytics`)
   - Note your project ID for later configuration

2. **Create a service account** for dbt access:

   - Go to IAM & Admin → Service Accounts
   - Create a new service account (e.g., `dbt-service-account`)
   - Grant the following roles:
     - BigQuery Data Editor
     - BigQuery Job User
     - BigQuery User

3. **Generate and download service account key**:
   - Click on your service account → Keys → Add Key → Create New Key
   - Choose JSON format
   - Download the key file

### Step 2: Secure Your Credentials

1. **Create a keys directory** in your project root:

   ```bash
   mkdir keys
   ```

2. **Move your service account key** to the keys directory:

   ```bash
   mv ~/Downloads/your-service-account-key.json keys/
   ```

3. **Add keys directory to .gitignore**:

   ```bash
   echo "keys/" >> .gitignore
   ```

4. **Verify .gitignore** contains:
   ```
   keys/
   ```

**⚠️ Security Note**: Never commit service account keys to version control. The
keys directory should always be in your .gitignore file.

### Step 3: Create Virtual Environment

1. **Create a virtual environment** with a descriptive name:

   ```bash
   python -m venv PROJECT-NAME-python
   ```

   Replace `PROJECT-NAME` with your actual project name (e.g.,
   `analytics-python`, `data-warehouse-python`).

2. **Activate the virtual environment**:

   ```bash
   # On macOS/Linux
   source PROJECT-NAME-python/bin/activate

   # On Windows
   PROJECT-NAME-python\Scripts\activate
   ```

3. **Verify activation** - your terminal prompt should show the virtual
   environment name in parentheses.

### Step 4: Install dbt

1. **Install dbt for your data warehouse**:

   ```bash
   # For BigQuery
   pip install dbt-bigquery

   # For other warehouses:
   # pip install dbt-snowflake  # Snowflake
   # pip install dbt-postgres   # PostgreSQL
   # pip install dbt-redshift   # Redshift
   ```

2. **Verify installation**:
   ```bash
   dbt --version
   ```

### Step 5: Initialize dbt Project

1. **Create your dbt project**:

   ```bash
   dbt init YOUR_PROJECT_NAME
   ```

2. **Navigate to your project directory**:
   ```bash
   cd YOUR_PROJECT_NAME
   ```

### Step 6: Configure dbt Profile

1. **Edit your dbt profile** at `~/.dbt/profiles.yml`:

   ```yaml
   YOUR_PROJECT_NAME:
     outputs:
       dev:
         type: bigquery
         method: service-account
         project: your-bigquery-project-id
         dataset: development
         keyfile: /absolute/path/to/keys/your-service-account-key.json
         location: US
         threads: 6
         timeout_seconds: 300
         job_execution_timeout_seconds: 300
         job_retries: 1
         priority: interactive
     target: dev
   ```

2. **Replace the following values**:
   - `YOUR_PROJECT_NAME`: Your dbt project name
   - `your-bigquery-project-id`: Your BigQuery project ID
   - `/absolute/path/to/keys/your-service-account-key.json`: Full path to your
     service account key file
   - `development`: Your target dataset/schema name

### Step 7: Verify Configuration

1. **Test your dbt connection**:

   ```bash
   dbt debug
   ```

2. **Expected output** should show:
   - ✅ Connection test passed
   - ✅ Profile configuration valid
   - ✅ Dependencies installed

### Step 8: Run Example Models

1. **Run the default example models**:

   ```bash
   dbt run
   ```

2. **Test the models**:

   ```bash
   dbt test
   ```

3. **Generate documentation**:

   ```bash
   dbt docs generate
   dbt docs serve
   ```

4. **View your models** in BigQuery:
   - Go to your BigQuery console
   - Navigate to your project → `development` dataset
   - You should see your example models as tables/views

---

## Install and Configure dbt-nexus

### Installation Methods

The dbt-nexus package can be installed in two ways depending on your use case:

- **Git Submodule**: For development and when you plan to make changes to the
  package
- **GitHub Repository**: For production deployments and when you only need to
  use the package

### Method 1: Git Submodule (Recommended for Development)

Use this method when you plan to make changes to the dbt-nexus package or want
to contribute to its development.

#### Step 1: Add the Submodule

1. **Navigate to your dbt project root**:

   ```bash
   cd your-dbt-project
   ```

2. **Add the dbt-nexus submodule**:

   ```bash
   git submodule add https://github.com/sliderule-analytics/dbt-nexus.git dbt-nexus
   ```

3. **Initialize and update the submodule**:
   ```bash
   git submodule update --init --recursive
   ```

#### Step 2: Configure packages.yml

Add the local submodule to your `packages.yml`:

```yaml
# packages.yml
packages:
  - local: dbt-nexus
```

#### Step 3: Install Dependencies

```bash
dbt deps
```

#### Managing Submodule Updates

To update the submodule to the latest version:

```bash
# Update the submodule to the latest version
git submodule update --remote dbt-nexus

# Commit the submodule update
git add dbt-nexus
git commit -m "Update dbt-nexus submodule to latest version"

# Reinstall dbt dependencies
dbt deps
```

### Method 2: GitHub Repository (Recommended for Production)

Use this method for production deployments when you only need to use the package
without making changes.

#### Step 1: Configure packages.yml

Add the GitHub repository to your `packages.yml`:

```yaml
# packages.yml
packages:
  - git: "https://github.com/sliderule-analytics/dbt-nexus.git"
    version: main # or specific version/tag
```

#### Step 2: Install Dependencies

```bash
dbt deps
```

#### Updating from GitHub

To update to the latest version:

```bash
dbt deps --upgrade
```

---

## Package Configuration

### Required Configuration

Add the following to your `dbt_project.yml`:

```yaml
vars:
  # Unified Nexus configuration
  nexus:
    max_recursion: 5 # Control recursion depth for identity resolution
    entity_types: ["person", "group"]

    # Define your data sources
    sources:
      shopify_partner:
        enabled: true
        events: true
        entities: ["group"]
        relationships: false

      gmail:
        enabled: true
        events: true
        entities: ["person"]
        relationships: false

      manual:
        enabled: true
        events: true
        entities: ["person", "group"]
        relationships: true

  # Optional: Override incremental behavior in development
  override_incremental: false # Set to true for full refresh in dev
```

### Source Configuration Details

Each source in the `nexus.sources` dictionary must specify:

- **`enabled`**: Whether this source is active (true/false)
- **`events`**: Whether this source provides event data
- **`entities`**: Which entity types this source provides (e.g., ["person",
  "group"])
- **`relationships`**: Whether this source provides entity relationships
  (person-group, etc.)

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
```

---

## Demo Data Setup

The dbt-nexus package includes comprehensive demo data that demonstrates all the
package's capabilities.

### Step 1: Build Demo Data

The demo data builds automatically when you run dbt commands because the package
includes its own default configuration:

```bash
# From your dbt project directory
dbt build
```

### Step 2: Run Specific Demo Sources

You can also run specific demo sources individually:

```bash
# Run specific demo sources
dbt run --models tag:nexus --select source:gmail
dbt run --models tag:nexus --select source:gadget
dbt run --models tag:nexus --select source:stripe

# List all demo models
dbt list --select package:nexus
```

### Step 3: Explore Demo Data

Once built, explore the demo data in BigQuery:

```sql
-- View all demo events
SELECT * FROM nexus_demo_data.nexus_events
ORDER BY occurred_at DESC;

-- View resolved persons
SELECT * FROM nexus_demo_data.nexus_persons;

-- View group memberships
SELECT
    p.name as person_name,
    g.name as group_name,
    m.role
FROM nexus_demo_data.nexus_memberships m
JOIN nexus_demo_data.nexus_persons p ON m.person_id = p.id
JOIN nexus_demo_data.nexus_groups g ON m.group_id = g.id;

-- View events by source
SELECT
    source,
    COUNT(*) as event_count
FROM nexus_demo_data.nexus_events
GROUP BY source;
```

---

## Local Development Setup

This guide covers setting up the dbt-nexus package for local development and
ensuring the dbt poweruser extension works properly.

### Prerequisites

- Python 3.8+ with virtual environment
- dbt-core installed
- VS Code with dbt poweruser extension

### Project Configuration

#### 1. dbt_project.yml Configuration

Ensure your `dbt_project.yml` includes the required `config-version`:

```yaml
name: "your_project_name"
version: "1.0.0"
config-version: 2 # Required for dbt poweruser extension

# ... rest of your configuration
```

#### 2. VS Code Settings

Create a `.vscode/settings.json` file in your dbt project root to configure the
dbt poweruser extension:

```json
{
  "python.defaultInterpreterPath": "/path/to/your/venv/bin/python",
  "python.experiments.enabled": false,
  "dbt.dbtPythonPathOverride": "/path/to/your/venv/bin/python",
  "dbt.enableNewLineagePanel": true
}
```

**Important**: Replace `/path/to/your/venv/bin/python` with the actual path to
your Python virtual environment where dbt is installed.

#### 3. Virtual Environment Setup

Create a `.commands` file in your project root to set up environment aliases:

```bash
source /path/to/your/venv/bin/activate
alias edit="code ./ &>/dev/null &"
alias run="dbt run"
alias run-refresh="dbt run --full-refresh"
alias deploy="dbt run --full-refresh --target prod"
alias run-nexus="dbt run --select package:nexus"
```

### Troubleshooting

#### dbt Poweruser Extension Not Working

If the dbt poweruser extension isn't working:

1. **Check config-version**: Ensure `config-version: 2` is in your
   `dbt_project.yml`
2. **Verify Python path**: Make sure the `dbt.dbtPythonPathOverride` in VS Code
   settings points to the correct Python environment
3. **Test dbt installation**: Run `dbt --version` from your project directory to
   ensure dbt is accessible
4. **Reload VS Code**: Restart VS Code or reload the dbt poweruser extension

#### ModuleNotFoundError: No module named 'dbt'

This error typically occurs when:

- The virtual environment isn't properly activated
- The VS Code settings point to the wrong Python environment
- dbt isn't installed in the specified Python environment

**Solution**: Update the `dbt.dbtPythonPathOverride` in your
`.vscode/settings.json` to point to the correct Python environment where dbt is
installed.

---

## Next Steps

After completing the getting started process:

1. **Enable template sources** - Configure Gmail, Google Calendar, or other
   template sources for instant integration
2. **Set up your ETL pipeline** - Configure the Nexus ETL pipeline for data
   syncing
3. **Build custom models** - Create analytics models using the unified nexus
   data
4. **Explore advanced features** - Dive into identity resolution and state
   management
5. **Scale to production** - Set up incremental processing and monitoring

### What You'll Learn

By following these guides, you'll:

- ✅ **Set up a production-ready dbt project** with proper virtual environments
  and security
- ✅ **Install the dbt-nexus package** using the method that fits your workflow
- ✅ **Configure template sources** like Gmail and Google Calendar with simple
  variables
- ✅ **Set up final table aliases** for easy model referencing
- ✅ **Configure schemas** for organized data warehouse structure
- ✅ **Understand the data flow** from raw sources to final unified tables
- ✅ **Explore unified customer data** across all your integrated sources

### Getting Help

- 📚 **Complete Documentation**:
  [https://sliderule-analytics.github.io/dbt-nexus](https://sliderule-analytics.github.io/dbt-nexus)
- 🐛 **Report Issues**:
  [GitHub Issues](https://github.com/sliderule-analytics/dbt-nexus/issues)
- 💬 **Community**: [dbt Community Slack](https://community.getdbt.com/)

---

**Ready to get started?** Begin with the project initialization steps above,
then move on to installing and configuring the dbt-nexus package.
