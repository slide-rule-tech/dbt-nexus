---
title: Quick Reference
tags: [ai-context, quick-reference, commands, configuration]
summary: Essential commands, configurations, and patterns for quick lookup.
---

# Quick Reference

## Installation Commands

### Git Submodule (Development)

```bash
git submodule add https://github.com/sliderule-analytics/dbt-nexus.git dbt-nexus
git submodule update --init --recursive
```

### GitHub Repository (Production)

```yaml
# packages.yml
packages:
  - git: "https://github.com/sliderule-analytics/dbt-nexus.git"
    version: main
```

## Essential Configuration

### dbt Project Configuration

```yaml
# dbt_project.yml
vars:
  nexus:
    max_recursion: 5
    entity_types: ["person", "group"]
    sources:
      your_source:
        enabled: true
        events: true
        entities: ["person"]
        relationships: true

models:
  nexus:
    nexus-models:
      final-tables:
        +schema: nexus_final_tables
      identity-resolution:
        +schema: nexus_identity_resolution
      event-log:
        +schema: nexus_event_log
```

## Key Commands

### Demo Data

```bash
# Build demo data
dbt build

# Run specific sources
dbt run --models tag:nexus --select source:gmail
dbt run --models tag:nexus --select source:stripe

# List all models
dbt list --select package:nexus
```

### Production Usage

```bash
# Run all nexus models
dbt run --select package:nexus

# Run specific model groups
dbt run --select package:nexus --models tag:final-tables
dbt run --select package:nexus --models tag:identity-resolution

# Test models
dbt test --select package:nexus
```

## Model Naming Conventions

### Source Models (v0.3.0 Entity-Centric Architecture)

- Events: `{source}_events`
- Entity Identifiers: `{source}_entity_identifiers` (unified person + group)
- Entity Traits: `{source}_entity_traits` (unified person + group)
- Relationship Declarations: `{source}_relationship_declarations` (replaces membership_identifiers)

#### Intermediate Layer (kept separate for DevX):
- Person Identifiers: `{source}_*_person_identifiers`
- Person Traits: `{source}_*_person_traits`
- Group Identifiers: `{source}_*_group_identifiers`
- Group Traits: `{source}_*_group_traits`
- Relationships: `{source}_*_relationship_declarations`

### Event Column Naming Strategy

**Prefixed Columns** (require `event_` prefix):

- `event_id`, `event_name`, `event_description`, `event_type` - Generic names
  that would conflict across sources

**Non-Prefixed Columns** (standard event tracking fields):

- `value`, `significance` - Standard event tracking fields (GA4 compatible)
- `occurred_at`, `source` - Standard timestamp and attribution fields

### Final Tables

- `nexus_persons` - Resolved person entities
- `nexus_groups` - Resolved group entities
- `nexus_events` - All events with resolved identifiers
- `nexus_memberships` - Person-group relationships
- `nexus_states` - Timeline-based state tracking

## Essential Macros

### Identity Resolution

- `resolve_identifiers()` - Recursive CTE-based deduplication
- `resolve_traits()` - Merge traits from resolved identities
- `create_edges()` - Build identity graph edges

### Event Processing

- `process_identifiers()` - Extract identifiers from events
- `process_traits()` - Extract traits from events
- `event_filter()` - Filter events by criteria

### State Management

- `derived_state()` - Create derived states from base states
- `common_state_fields()` - Standard state model fields

## Schema Organization

### Recommended Schemas

- `nexus_final_tables` - Production-ready resolved entities
- `nexus_identity_resolution` - Identity resolution models
- `nexus_event_log` - Event processing models
- `nexus_sources` - Source-specific models

### Demo Schemas

- `demo_raw` - Raw seed data
- `sources_demo` - Source event log models
- `event_log_demo` - Core event log models
- `identity_resolution_demo` - Identity resolution models
- `final_tables_demo` - Final unified tables

## State Naming Convention

Format: `{namespace}_{subject}[_{qualifier}]`

Examples:

- `billing_lifecycle`
- `sliderule_app_installation`
- `support_ticket_status`

## Common Patterns

### Alias Models

```sql
-- models/final-tables/persons.sql
select * from {{ ref('nexus_persons') }}
```

### Custom State Model

```sql
-- models/states/billing_lifecycle.sql
select
    person_id,
    'active' as state,
    started_at as state_entered_at,
    ended_at as state_exited_at,
    case when ended_at is null then true else false end as is_current
from {{ ref('billing_events') }}
```

### Event Filtering

```sql
select *
from {{ ref('nexus_events') }}
where {{ event_filter('billing', 'subscription_created') }}
```

## Data Quality Best Practices

### Source Data Validation

- **Explicit field selection** - Avoid `SELECT *` in normalized layer
- **Null handling** - Use `LEFT JOIN` to preserve all records
- **Data type consistency** - Ensure compatible types across sources
- **Deduplication** - Remove duplicates in normalized layer

### Common Data Issues

- **ID mismatches** - Track join success rates between related tables
- **Missing timestamps** - Filter out events without `occurred_at`
- **Schema drift** - Monitor for unexpected column changes
- **Data freshness** - Implement incremental strategies for large sources

## Troubleshooting Quick Fixes

### Identity Resolution Issues

- Check `nexus_max_recursion` setting
- Verify source model naming conventions
- Review data quality in identifier columns
- Use `dbt_utils.union_relations()` for robust unioning

### Performance Issues

- Adjust `nexus_max_recursion` value
- Review incremental model strategies
- Consider partitioning for large datasets
- Use four-layer architecture for better organization

### Missing Models

- Verify `sources` variable configuration
- Check model naming conventions
- Run `dbt list --select package:nexus` to see available models
- Ensure proper directory structure (base/normalized/intermediate)
