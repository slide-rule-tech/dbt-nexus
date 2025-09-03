---
title: Setting up the dbt-nexus Package
tags: [quickstart, installation, dbt-nexus, submodule, github]
summary:
  Quick guide to installing the dbt-nexus package either as a git submodule for
  development or from GitHub for production, including demo data setup and
  schema configuration.
---

# Set up the dbt-nexus Package

This guide covers how to install the
[dbt-nexus package](https://github.com/sliderule-analytics/dbt-nexus) in your
dbt project, including different installation methods, demo data setup, and
schema configuration.

---

## Installation Methods

The dbt-nexus package can be installed in two ways depending on your use case:

- **Git Submodule**: For development and when you plan to make changes to the
  package
- **GitHub Repository**: For production deployments and when you only need to
  use the package

---

## Method 1: Git Submodule (Recommended for Development)

Use this method when you plan to make changes to the dbt-nexus package or want
to contribute to its development.

### Step 1: Add the Submodule

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

### Step 2: Configure packages.yml

Add the local submodule to your `packages.yml`:

```yaml
# packages.yml
packages:
  - local: dbt-nexus
```

### Step 3: Install Dependencies

```bash
dbt deps
```

### Managing Submodule Updates

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

---

## Method 2: GitHub Repository (Recommended for Production)

Use this method for production deployments when you only need to use the package
without making changes.

### Step 1: Configure packages.yml

Add the GitHub repository to your `packages.yml`:

```yaml
# packages.yml
packages:
  - git: "https://github.com/sliderule-analytics/dbt-nexus.git"
    version: main # or specific version/tag
```

### Step 2: Install Dependencies

```bash
dbt deps
```

### Updating from GitHub

To update to the latest version:

```bash
dbt deps --upgrade
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

### Demo Data Schema Organization

The demo data uses a structured schema approach:

- **`demo_raw`** - Raw seed data (CSV files)
- **`sources_demo`** - Source event log models
- **`event_log_demo`** - Core event log models
- **`identity_resolution_demo`** - Identity resolution models
- **`final_tables_demo`** - Final unified tables (persons, groups, events,
  states)

---

## Configuration

### Step 1: Configure Recursion Control

The dbt-nexus package uses recursive CTEs for entity resolution. Control the
maximum recursion depth in your `dbt_project.yml`:

```yaml
# dbt_project.yml
vars:
  nexus_max_recursion: 5 # Set to your preferred recursion limit
```

### Step 2: Alias Final Tables (Recommended)

To make the nexus final tables easily accessible in your dbt project, create
simple alias models that reference the nexus package models. This approach has
minimal performance impact since the aliases are not materialized.

Create the following models in your project:

**`models/final-tables/persons.sql`**:

```sql
select * from {{ ref('nexus_persons') }}
```

**`models/final-tables/groups.sql`**:

```sql
select * from {{ ref('nexus_groups') }}
```

**`models/final-tables/events.sql`**:

```sql
select * from {{ ref('nexus_events') }}
```

**`models/final-tables/states.sql`**:

```sql
select * from {{ ref('nexus_states') }}
```

**Link Tables** (in `models/final-tables/links/`):

**`models/final-tables/links/memberships.sql`**:

```sql
select * from {{ ref('nexus_memberships') }}
```

**`models/final-tables/links/person_identifiers.sql`**:

```sql
select * from {{ ref('nexus_person_identifiers') }}
```

**`models/final-tables/links/group_identifiers.sql`**:

```sql
select * from {{ ref('nexus_group_identifiers') }}
```

**`models/final-tables/links/person_participants.sql`**:

```sql
select * from {{ ref('nexus_person_participants') }}
```

**`models/final-tables/links/group_participants.sql`**:

```sql
select * from {{ ref('nexus_group_participants') }}
```

These alias models allow you to:

- **Easily reference** nexus tables in your own models using
  `{{ ref('persons') }}`
- **View results** directly in your dbt project's lineage graph
- **Maintain consistency** with your project's naming conventions
- **Minimize performance impact** since aliases are not materialized by default

**Note**: The `select * from {{ ref('...') }}` pattern is effectively an alias
because it's not materialized and has very little performance impact.

---

## Schema Configuration

### Default Schema Behavior

By default, the dbt-nexus package creates models in schemas defined in its own
`dbt_project.yml`:

- Demo schemas: `demo_raw`, `sources_demo`, `event_log_demo`, etc.
- Production schemas: `nexus` (or your target schema)

### Overriding Schema Settings

To customize where the nexus models are built, configure them in your main
project's `dbt_project.yml`:

```yaml
# dbt_project.yml - RECOMMENDED PRODUCTION CONFIGURATION
models:
  your_project_name: # Replace with your dbt project name
    # Your project models configuration
    example:
      +materialized: view
    sources:
      +schema: nexus_sources
      +tags: ["nexus"]

  nexus: # Use the package name, not the submodule name
    nexus-models:
      final-tables:
        +schema: nexus_final_tables
      states:
        +schema: nexus_final_tables
      identity-resolution:
        +schema: nexus_identity_resolution
      event-log:
        +schema: nexus_event_log
        nexus_events:
          +schema: nexus_final_tables
```

### Recommended Schema Organization

The configuration above organizes models into logical schemas based on the
layers shown in the [database schema diagram](../index.md#image):

- **`nexus_final_tables`** - Final unified tables (persons, groups, events,
  states)
- **`nexus_identity_resolution`** - Identity resolution models
- **`nexus_event_log`** - Event log models
- **`nexus_sources`** - Your source models

## Usage Examples

### Referencing Nexus Models

Once installed and configured, reference nexus models in your own dbt models:

```sql
-- your_model.sql
select
    person_id,
    email,
    name,
    created_at
from {{ ref('nexus_persons') }}
where created_at >= current_date - interval 7 days
```

### Running Nexus Models

```bash
# Run all nexus models
dbt run --select package:nexus

# Run specific nexus model groups
dbt run --select package:nexus --models tag:final-tables
dbt run --select package:nexus --models tag:identity-resolution

# Test nexus models
dbt test --select package:nexus
```

---

## Troubleshooting

### Installation Issues

1. **Submodule not updating**: Ensure you're using
   `git submodule update --remote`
2. **Package not found**: Verify the path in `packages.yml` is correct
3. **Version conflicts**: Check dbt version compatibility (requires dbt >=
   1.0.0)

### Configuration Issues

1. **Models not building**: Check that your `sources` variable is properly
   configured
2. **Schema errors**: Verify schema configuration follows the single `models:`
   section rule
3. **Recursion errors**: Adjust `nexus_max_recursion` value if needed

### Demo Data Issues

1. **Demo data not building**: Ensure you haven't overridden the package's
   `vars` configuration
2. **Missing models**: Run `dbt list --select package:nexus` to see available
   models
3. **Permission errors**: Verify your service account has BigQuery permissions

---

## Next Steps

1. **Configure your data sources** in the `sources` variable
2. **Create source models** following the naming convention
3. **Run the nexus models** to process your data
4. **Build custom models** that reference nexus outputs
5. **Set up tests and documentation** for your models

---

## Related Documentation

- [dbt-nexus GitHub Repository](https://github.com/sliderule-analytics/dbt-nexus)
- [dbt-nexus Documentation](https://sliderule-analytics.github.io/dbt-nexus)
- [dbt Package Management](https://docs.getdbt.com/docs/package-management)
- [dbt Project Configuration](https://docs.getdbt.com/docs/project-configs)
