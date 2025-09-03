---
title: Quickstart: Initialize a New dbt Project
tags: [quickstart, dbt, setup, bigquery]
summary: Step-by-step guide to set up a new dbt project with best practices for virtual environments, BigQuery configuration, and project structure.
---

# Quickstart: Initialize a New dbt Project

This guide walks you through setting up a new dbt project following best
practices for virtual environments, data warehouse configuration, and project
structure.

---

## Prerequisites

Before you begin, ensure you have the following installed:

1. **Python 3.7+** - Required for dbt and Python dependencies
2. **Git** - For version control
3. **Data Warehouse Access** - BigQuery project with appropriate permissions

---

## Step 1: Set Up Your Data Warehouse

### BigQuery Setup

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

---

## Step 2: Secure Your Credentials

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

---

## Step 3: Create Virtual Environment

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

---

## Step 4: Install dbt

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

---

## Step 5: Initialize dbt Project

1. **Create your dbt project**:

   ```bash
   dbt init YOUR_PROJECT_NAME
   ```

2. **Navigate to your project directory**:
   ```bash
   cd YOUR_PROJECT_NAME
   ```

---

## Step 6: Configure dbt Profile

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

---

## Step 7: Verify Configuration

1. **Test your dbt connection**:

   ```bash
   dbt debug
   ```

2. **Expected output** should show:
   - ✅ Connection test passed
   - ✅ Profile configuration valid
   - ✅ Dependencies installed

---

## Step 8: Run Example Models

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

## Project Structure

After initialization, your project should look like this:

```
YOUR_PROJECT_NAME/
├── dbt_project.yml          # dbt project configuration
├── packages.yml             # dbt package dependencies
├── models/                  # dbt models (SQL transformations)
│   └── example/             # Example models
├── analyses/                # dbt analyses
├── macros/                  # dbt macros (reusable SQL)
├── seeds/                   # dbt seeds (CSV data)
├── snapshots/               # dbt snapshots
├── tests/                   # dbt tests
└── target/                  # dbt build artifacts
```

---

## Next Steps

1. **Create your first custom model** in `models/`
2. **Set up data sources** and configure your first transformations

---

## Common Issues

### Connection Errors

- Run `dbt debug` to diagnose connection issues
- Verify service account has proper BigQuery permissions
- Check that the keyfile path is correct and accessible

### Virtual Environment Issues

- Ensure you're using the correct virtual environment
- Verify dbt is installed in the virtual environment, not globally
- Reactivate the virtual environment if needed

### Permission Errors

- Verify service account has required BigQuery roles
- Check that the service account key is valid and not expired

---

## Best Practices Summary

1. ✅ **Always use virtual environments** for project isolation
2. ✅ **Secure credentials** - never commit keys to version control
3. ✅ **Use descriptive naming** for projects and environments
4. ✅ **Test connections** before building models
5. ✅ **Start with example models** to verify setup
6. ✅ **Document your configuration** for team members

---

**Related Documentation**:

- [dbt Documentation](https://docs.getdbt.com/docs/introduction)
- [BigQuery dbt Adapter](https://github.com/dbt-labs/dbt-bigquery)
- [dbt Community Slack](https://community.getdbt.com/)
