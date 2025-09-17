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

**Critical Step**: Add the `enabled` variable to all models to make them
configurable:

```sql
{{ config(
    enabled=var('nexus', {}).get('your_source', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}
```

**Apply to ALL models:**

- Base models
- Event models
- Identifier models
- Trait models
- Membership models

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

Verify the migration works correctly:

```bash
# Test in client project
cd client-project
dbt run --select package:nexus

# Check that models are created
dbt run --select your_source_events
dbt run --select your_source_person_identifiers
```

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

## Best Practices

1. **Always add enabled configuration** to all models
2. **Test thoroughly** before removing client project files
3. **Update documentation** to reflect template source usage
4. **Use consistent naming** patterns across template sources
5. **Follow the established structure** (base/, events, identifiers, traits,
   memberships)
6. **Include comprehensive examples** in documentation
7. **Test with multiple client projects** to ensure reusability

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
