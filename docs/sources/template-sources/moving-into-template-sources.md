---
title: Moving Sources into Template Sources
tags: [template-sources, migration, guide, sources]
summary:
  Complete guide for migrating custom source models into reusable template
  sources within the dbt-nexus package
---

# Moving Sources into Template Sources

This guide explains how to migrate custom source models from client projects
into reusable template sources within the dbt-nexus package. Template sources
provide standardized, configurable integrations that can be shared across
multiple projects.

## Overview

Template sources offer several advantages over custom source models:

- **🔄 Reusability**: One implementation serves multiple client projects
- **⚙️ Configuration**: Enable/disable and customize via `dbt_project.yml`
- **📚 Documentation**: Centralized, comprehensive documentation
- **🧪 Testing**: Consistent testing across all implementations
- **🔧 Maintenance**: Single codebase to maintain and update

## Migration Process

### Step 1: Analyze Current Source Structure

Before migrating, understand your current source implementation:

```bash
# Examine the source directory structure
ls -la models/sources/your_source/

# Check for base models, identifiers, traits, and events
find models/sources/your_source/ -name "*.sql" -type f
```

**Key Files to Identify:**

- Base model (transforms raw data)
- Event model (creates nexus events)
- Person identifiers/traits
- Group identifiers/traits
- Membership identifiers
- Source definition (`.yml` file)
- Documentation (`.md` file)

### Step 2: Create Template Source Structure

Create the template source directory in dbt-nexus:

```bash
# Create main directory
mkdir -p dbt-nexus/models/sources/your_source/

# Create base subdirectory if needed
mkdir -p dbt-nexus/models/sources/your_source/base/
```

### Step 3: Copy and Adapt Source Files

Copy all source files from client project to dbt-nexus:

```bash
# Copy SQL files
cp client-project/models/sources/your_source/*.sql dbt-nexus/models/sources/your_source/

# Copy YAML files
cp client-project/models/sources/your_source/*.yml dbt-nexus/models/sources/your_source/

# Copy documentation
cp client-project/models/sources/your_source/*.md dbt-nexus/models/sources/your_source/

# Copy base models
cp client-project/models/sources/your_source/base/*.sql dbt-nexus/models/sources/your_source/base/
```

### Step 4: Add Enabled Variable Configuration

**Critical Step**: Add the `enabled` variable to **ALL MODELS** in the source to
make them configurable:

```sql
{{ config(
    enabled=var('nexus', {}).get('your_source', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}
```

**Apply to ALL models without exception:**

- Base models (all files in `base/` directory)
- Event models
- Identifier models
- Trait models
- Membership models
- Cleaned/intermediate models
- Any other SQL files in the source

**⚠️ Critical**: Every single `.sql` file in the source directory must have the
enabled configuration. Missing this on even one model will cause compilation
errors when the source is disabled.

**Important**: For sources that don't have universal defaults (like Segment),
consider removing hardcoded defaults to force explicit client configuration.

### Step 5: Update dbt-nexus Package Configuration

Add your source to the dbt-nexus package configuration:

```yaml
# dbt-nexus/dbt_project.yml
vars:
  nexus:
    your_source:
      enabled: false # Default to disabled
      location:
        schema: your_source_schema
        table: your_source_table
      capabilities:
        events: true
        persons: true
        groups: true
        memberships: true
```

### Step 5a: Handle Database-Specific Requirements

**For Snowflake compatibility**, ensure your source configuration supports the
three-part naming convention:

```yaml
# dbt-nexus/dbt_project.yml
vars:
  nexus:
    your_source:
      enabled: false
      location:
        database: "" # Empty default for flexibility
        schema: your_source_schema
        table: your_source_table
        # For sources with multiple tables (like Segment)
        tables:
          table1: TABLE1
          table2: TABLE2
```

**For sources without universal defaults** (like Segment), remove hardcoded
defaults:

```yaml
# Instead of: schema: 'DEFAULT_SCHEMA'
# Use: schema: var('nexus', {}).get('your_source', {}).get('location', {}).get('schema')
```

### Step 5b: Update Source References for Dynamic Resolution

**Use the `nexus_source` macro** for dynamic source resolution instead of
hardcoded source references:

```sql
-- Instead of: select * from {{ source('HARDCODED_SCHEMA', 'HARDCODED_TABLE') }}
-- Use: select * from {{ nexus_source('your_source', 'table_name') }}
```

**Update base models** to use the macro:

```sql
-- base/your_source_table_base.sql
select * from {{ nexus_source('your_source', 'table_name') }}
```

**Update source definitions** to use Jinja templating with fallback defaults:

```yaml
# your_source.yml
sources:
  - name:
      "{{ var('nexus', {}).get('your_source', {}).get('location',
      {}).get('schema', 'your_source_disabled') }}"
    database:
      "{{ var('nexus', {}).get('your_source', {}).get('location',
      {}).get('database', '') }}"
    tables:
      - name:
          "{{ var('nexus', {}).get('your_source', {}).get('location',
          {}).get('tables', {}).get('table_name', 'DEFAULT_TABLE') }}"
```

**⚠️ Critical YAML Configuration**: Always provide fallback defaults in YAML
templating to prevent `None` values that cause validation errors when the source
is disabled. The schema name fallback should indicate the disabled state (e.g.,
`'your_source_disabled'`).

### Step 6: Create Template Documentation

Create comprehensive documentation in
`docs/template-sources/your_source/index.md`:

```markdown
---
title: Your Source Template Source
tags: [template-sources, your-source, configuration]
summary:
  Ready-to-use Your Source integration for events, person identifiers, and group
  relationships
---

# Your Source Template Source

[Comprehensive documentation following the template source pattern...]
```

### Step 7: Update Client Project Configuration

Remove the source from client project's legacy sources list and configure as
template source:

```yaml
# client-project/dbt_project.yml

# Remove from legacy sources section
sources:
  # - name: your_source  # Remove this
  #   events: true
  #   groups: true
  #   persons: true
  #   memberships: true

# Add to nexus configuration
vars:
  nexus:
    your_source:
      enabled: true # Enable the template source
      # Optional: Override default location
      # location:
      #   schema: custom_schema
      #   table: custom_table
```

### Step 8: Remove Client Project Files

Clean up the client project by removing the migrated source files:

```bash
# Remove the source directory from client project
rm -rf client-project/models/sources/your_source/
```

### Step 9: Test the Migration

**⚠️ CRITICAL**: Always test both enabled AND disabled states before deploying a
nexus version.

#### Test Enabled State

```bash
# Test in client project with source enabled
cd client-project
dbt run --select package:nexus

# Check that models are created
dbt run --select your_source_events
dbt run --select your_source_person_identifiers
```

#### Test Disabled State (MANDATORY)

**This step is critical and must not be skipped**:

```bash
# Test with source disabled
# Set nexus.your_source.enabled: false in dbt_project.yml

# Test compilation (should not fail)
dbt compile --select package:nexus

# Test parsing (should not fail)
dbt parse

# Test that disabled models don't run
dbt run --select package:nexus
# Should skip your_source models

# Test that other nexus models still work
dbt run --select events persons groups
```

**Common Issues When Disabled**:

- `'NoneType' object is not iterable` → Missing enabled config on a model
- `None is not of type 'string'` → Missing fallback defaults in YAML
- `Source not found` → Hardcoded source references instead of nexus_source macro

#### Test Multiple Client Projects

Test the template source with different client configurations:

```bash
# Test with different schema names
# Test with different table names
# Test with minimal configuration
# Test with full configuration
```

## Example: Segment Migration

Here's how we migrated Segment from a client project to a template source,
including the specific challenges and solutions we encountered:

### Before Migration

**Client Project Structure:**

```
client-projects/gameday_dbt/models/sources/segment/
├── base/
│   ├── base_segment_tracks.sql
│   ├── base_segment_pages.sql
│   └── base_segment_identifies.sql
├── segment_events.sql
├── segment_person_identifiers.sql
├── segment_person_traits.sql
├── segment_touchpoints.sql
└── segment.yml
```

**Key Challenges Encountered:**

- NoneType iteration error in attribution models
- Hardcoded source references not compatible with Snowflake
- Missing database parameter for three-part naming
- Case sensitivity issues between YAML and database

### After Migration

**dbt-nexus Template Source:**

```
dbt-nexus/models/sources/segment/
├── base/
│   ├── base_segment_tracks.sql      # Uses nexus_source macro
│   ├── base_segment_pages.sql       # Uses nexus_source macro
│   └── base_segment_identifies.sql  # Uses nexus_source macro
├── segment_events.sql
├── segment_person_identifiers.sql
├── segment_person_traits.sql
├── segment_touchpoints.sql
├── segment.yml                      # Dynamic Jinja templating
└── docs/template-sources/segment/
    └── index.md
```

**Key Fixes Applied:**

- Added `referral_exclusions` variable to prevent NoneType errors
- Updated `nexus_source` macro to handle database parameter
- Implemented dynamic source resolution with Jinja templating
- Removed hardcoded defaults to force explicit configuration
- Added Snowflake compatibility with three-part naming

## Example: Google Calendar Migration

Here's how we migrated Google Calendar from a client project to a template
source:

### Before Migration

**Client Project Structure:**

```
client-projects/slide_rule_tech/models/sources/google_calendar/
├── base/
│   └── google_calendar_events_base.sql
├── google_calendar_events.sql
├── google_calendar_person_identifiers.sql
├── google_calendar_person_traits.sql
├── google_calendar_group_identifiers.sql
├── google_calendar_group_traits.sql
├── google_calendar_membership_identifiers.sql
├── google_calendar.yml
└── GOOGLE_CALENDAR_SOURCE.md
```

**Client Configuration:**

```yaml
# dbt_project.yml
sources:
  - name: google_calendar
    events: true
    groups: true
    persons: true
    memberships: true
```

### After Migration

**dbt-nexus Template Source:**

```
dbt-nexus/models/sources/google_calendar/
├── base/
│   └── google_calendar_events_base.sql  # With enabled config
├── google_calendar_events.sql           # With enabled config
├── google_calendar_person_identifiers.sql  # With enabled config
├── google_calendar_person_traits.sql    # With enabled config
├── google_calendar_group_identifiers.sql  # With enabled config
├── google_calendar_group_traits.sql     # With enabled config
├── google_calendar_membership_identifiers.sql  # With enabled config
├── google_calendar.yml
└── GOOGLE_CALENDAR_SOURCE.md
```

**Client Configuration:**

```yaml
# dbt_project.yml
vars:
  nexus:
    google_calendar:
      enabled: true
# sources: section updated with comment explaining template source
```

## Configuration Patterns

### Basic Template Source Configuration

```yaml
# dbt_project.yml
vars:
  nexus:
    your_source:
      enabled: true # Enable the template source
```

### Custom Source Location

```yaml
vars:
  nexus:
    your_source:
      enabled: true
      location:
        schema: custom_schema
        table: custom_table
```

### Advanced Configuration

```yaml
vars:
  nexus:
    your_source:
      enabled: true
      location:
        schema: your_data_schema
        table: your_data_table
      capabilities:
        events: true
        persons: true
        groups: true
        memberships: true
```

## Model Configuration Pattern

All template source models should follow this pattern:

```sql
{{ config(
    enabled=var('nexus', {}).get('your_source', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

-- Your model logic here
```

## Verification Checklist

After migration, verify:

- [ ] All models have `enabled` variable configuration
- [ ] Template source is configured in dbt-nexus `dbt_project.yml`
- [ ] Client project has `nexus.your_source.enabled: true`
- [ ] Client project removed source from legacy `sources` list
- [ ] Documentation exists in `docs/template-sources/your_source/`
- [ ] All models run successfully with `dbt run --select package:nexus`
- [ ] Data flows correctly to nexus final tables

## Common Issues

### Models Not Building

**Problem**: Template source models don't appear in `dbt run`

**Solution**: Check that `nexus.your_source.enabled: true` is set in client
project

### Missing Enabled Configuration

**Problem**: Models build even when disabled

**Solution**: Ensure all models have the `enabled` variable configuration

### Source Not Found Errors

**Problem**: References to old source models fail

**Solution**: Update any custom models that reference the old source models

### Configuration Conflicts

**Problem**: Both legacy source and template source are configured

**Solution**: Remove the source from the legacy `sources` list in client project

### Compilation Errors

**Problem**: "NoneType object is not iterable" error

**Solution**: Ensure all required variables are configured in the nexus package
(e.g., `referral_exclusions` for attribution sources)

**Problem**: "Source not found" error with correct configuration

**Solution**: Check table name casing - YAML uses lowercase, database may use
uppercase

**Problem**: "Schema does not exist" error

**Solution**: Verify the schema name in configuration matches your actual
database schema

### YAML Configuration Errors

**Problem**: `None is not of type 'string'` in source YAML validation

**Root Cause**: When a template source is disabled, Jinja variables in the YAML
return `None`, causing dbt's YAML validation to fail.

**Solution**: Always provide fallback defaults in YAML templating:

```yaml
# ❌ Wrong - will cause validation error when disabled
sources:
  - name: "{{ var('nexus', {}).get('your_source', {}).get('location', {}).get('schema') }}"

# ✅ Correct - provides fallback default
sources:
  - name: "{{ var('nexus', {}).get('your_source', {}).get('location', {}).get('schema', 'your_source_disabled') }}"
```

**Additional Steps**:

1. Add default values in the nexus package `dbt_project.yml`:
   ```yaml
   nexus:
     your_source:
       enabled: false
       location:
         schema: your_source_disabled
         database: ""
   ```
2. Ensure all YAML template variables have fallback defaults
3. Test compilation with the source disabled to verify the fix

### Snowflake-Specific Issues

**Problem**: "Schema 'DATABASE.SCHEMA' does not exist" error

**Solution**: Ensure the `database` parameter is configured in your source
definition

**Problem**: Duplicate source names

**Solution**: Clean target directory and reinstall packages:
`dbt clean && dbt deps`

**Problem**: Three-part naming not working

**Solution**: Use the `nexus_source` macro instead of direct `source()` calls

## Best Practices

1. **Always add enabled configuration** to ALL models (every .sql file in the
   source)
2. **MANDATORY: Test disabled state** before deploying any nexus version
3. **Test thoroughly** before removing client project files
4. **Update documentation** to reflect template source usage
5. **Use consistent naming** patterns across template sources
6. **Follow the established structure** (base/, events, identifiers, traits,
   memberships)
7. **Include comprehensive examples** in documentation
8. **Test with multiple client projects** to ensure reusability
9. **Use the `nexus_source` macro** for dynamic source resolution
10. **Handle database-specific requirements** (e.g., Snowflake three-part
    naming)
11. **Remove hardcoded defaults** for sources without universal standards
12. **Configure all required variables** to prevent compilation errors
13. **Test compilation** before running models to catch configuration issues
    early
14. **Handle case sensitivity** properly between YAML and database systems
15. **Clean target directory** when encountering duplicate source errors
16. **Always provide YAML fallback defaults** to prevent None validation errors
17. **Test both enabled and disabled states** in multiple client environments

## Next Steps

After successfully migrating a source to a template source:

- [Update the template sources index](../index.md) to include your new source
- [Create migration guides](../../how-to/) for other teams
- [Add to the quickstart guide](../../quickstart/) if it's a common source
- [Consider creating tests](../../reference/testing.md) for the template source

---

**Need help with migration?** Check the
[troubleshooting guide](../../explanations/troubleshooting.md) or review
existing template sources like [Gmail](../gmail/) and
[Google Calendar](../google_calendar/) for reference patterns.
