---
title: dbt-nexus LLM Context Pack
tags: [llm, context, nexus, identity-resolution, ai-context]
summary:
  Compact briefing for LLMs that need to answer questions about the dbt-nexus
  package. Essential context for AI assistants working with customer identity
  resolution and event tracking.
---

# dbt-nexus LLM Context Pack

## Mission

The dbt-nexus package provides a way of structuring all company data in your
data warehouse so it's **operationally useful**, not just good for dashboards.
It's designed to help close sales, speed up customer support, and reduce churn
by creating complete customer timelines from any data source.

Specifically, it's a standardized, source-agnostic dbt framework that lets data
engineers quickly merge and organize **any** data source into a combined view of
**people**, **companies**, and **events**. This enables organizations to
consolidate scattered customer data (Gmail, Stripe, Shopify, etc.) into unified
timelines that support teams, sales teams, and AI tools can actually use
operationally.

## Core Concepts

### Primary Entities

- **Persons**: Individual entities with identifiers (email, phone, etc.) and
  traits (name, age, etc.)
- **Groups**: Organizational entities (companies, accounts) with their own
  identifiers and traits
- **Events**: Timestamped actions/occurrences that generate identifiers, traits,
  and state changes
- **Memberships**: Relationships connecting persons to groups with optional
  roles

### Key Processes

- **Identity Resolution**: Recursive CTE-based deduplication using configurable
  matching rules
- **State Management**: Timeline-based state tracking with derived state
  capabilities
- **Event Processing**: Standardized event logging with identifier and trait
  extraction
- **Source Integration**: Adapter pattern for connecting any data source

## Architecture Layers

1. **Source Adapters**: Transform source data into standardized formats
2. **Event Log**: Core models for events, identifiers, traits (`nexus_events`,
   `nexus_person_identifiers`, etc.)
3. **Identity Resolution**: Deduplication logic producing resolved entities
   (`nexus_resolved_person_identifiers`)
4. **State Management**: Timeline tracking with derived states (`nexus_states`)
5. **Final Tables**: Production-ready resolved entities (`nexus_persons`,
   `nexus_groups`)

## Demo Data

The package includes comprehensive demo data for exploration and testing:

### Demo Data Sources

- **Gadget Shopify App Data**: Shopify shop information from custom Shopify app
  built in Gadget
- **Gmail Messages**: Email records with support tickets, billing communications
- **Google Calendar**: Calendar events with meetings and appointments
- **Stripe Data**: Billing and payment records with subscriptions

### Demo Data Usage

- **Location**: `dbt_packages/nexus/` directory
- **Schema**: Compiles to `nexus_demo_data` schema
- **Running**: `cd dbt_packages/nexus && dbt build`
- **Configuration**: Requires `demo-data: +schema: demo_data` in consumer
  `dbt_project.yml`

### Demo Data Value

- Complete working example of the dbt-nexus data model
- Multi-source customer journey scenarios
- Identity resolution examples across sources
- Realistic event timelines and state management

## Canonical Entry Points

### Key Models

- **Event Log**: `nexus_events`, `nexus_person_identifiers`,
  `nexus_person_traits`, `nexus_group_identifiers`, `nexus_group_traits`,
  `nexus_membership_identifiers`
- **Identity Resolution**: `nexus_resolved_person_identifiers`,
  `nexus_resolved_person_traits`, `nexus_resolved_group_identifiers`,
  `nexus_resolved_group_traits`
- **Final Tables**: `nexus_persons`, `nexus_groups`, `nexus_memberships`,
  `nexus_person_participants`, `nexus_group_participants`
- **States**: `nexus_states` (union of all state models)

### Essential Macros

- **Identity Resolution**: `resolve_identifiers()`, `resolve_traits()`,
  `create_edges()`
- **Event Processing**: `process_identifiers()`, `process_traits()`,
  `event_filter()`
- **State Management**: `derived_state()`, `common_state_fields()`
- **Utilities**: `unpivot_identifiers()`, `pivot_identifiers()`,
  `get_first_or_last_row()`, `finalize_entity()`

### Critical Configuration

- **`nexus_max_recursion`**: Controls recursive CTE depth for identity
  resolution (default: 5)
- **`sources`**: List defining which source systems provide which entity types
- **`nexus` model configs**: Schema, materialization, and tag settings

## Source Integration Pattern

### Four-Layer Architecture

Sources should follow a four-layer architecture pattern for optimal
organization:

1. **Base Layer**: Raw `SELECT *` from source tables (e.g.,
   `base_{source}_{table}`)
2. **Normalized Layer**: Clean, joined business entities (e.g.,
   `{source}_{entity}`)
3. **Intermediate Layer**: Event-type specific formatting using Nexus macros
4. **Unioned Layer**: Combined models using `dbt_utils.union_relations()`

### Model Naming Convention

Sources must provide models following naming convention
`{source_name}_{entity_type}_{data_type}`:

- Events: `{source}_events`
- Identifiers: `{source}_person_identifiers`, `{source}_group_identifiers`
- Traits: `{source}_person_traits`, `{source}_group_traits`
- Memberships: `{source}_membership_identifiers`

### Recommended Directory Structure

```
models/sources/{source_name}/
├── base/
│   ├── base_{source}_table1.sql
│   └── base_{source}_table2.sql
├── normalized/
│   ├── {source}_orders.sql
│   └── {source}_customers.sql
├── intermediate/
│   ├── {source}_order_events.sql
│   ├── {source}_order_person_identifiers.sql
│   └── {source}_order_person_traits.sql
└── {source}_events.sql
```

## State Management

States follow format `{namespace}_{subject}[_{qualifier}]` (e.g.,
`billing_lifecycle`, `sliderule_app_installation`). Each state model tracks
timeline changes with `state_entered_at`, `state_exited_at`, and `is_current`
fields. Derived states combine multiple base states using timeline merging
logic.

## Gotchas & Important Notes

### Database Compatibility

- **Primary support**: Snowflake and BigQuery (both fully tested and optimized)
- **Secondary**: Postgres, Redshift, Databricks
- Database-specific optimizations available for both Snowflake and BigQuery
- Recursive CTEs behave differently across warehouses

### Performance Considerations

- Recursive identity resolution can be expensive; tune `nexus_max_recursion`
  carefully
- Incremental models require careful handling of late-arriving data
- Large identity graphs may need partitioning strategies

### Common Pitfalls

- Source models must exactly match expected schema (column names, types)
- Identity resolution assumes transitivity (A=B, B=C → A=C)
- State models require manual addition to `nexus_states` union
- Event filtering depends on proper `_ingested_at` timestamps

### Incremental Model Behavior

- Event log models use `_ingested_at` for incremental filtering
- Identity resolution models may need full refresh when logic changes
- State models track changes over time, not point-in-time snapshots

## Quick Reference

### Common Tasks

- **Explore demo data**: `cd dbt_packages/nexus && dbt build` to run demo data
- **Add new source**: Define in `sources` var, create `{source}_{entity}_{type}`
  models
- **Create custom state**: Make individual state model, add to `nexus_states`
  union
- **Debug identity resolution**: Check `nexus_{entity}_identifiers_edges` for
  edge creation
- **Performance tuning**: Adjust `nexus_max_recursion`, review incremental
  strategies

### Troubleshooting

- **Missing identities**: Verify source model naming and schema compliance
- **Recursive CTE errors**: Check `nexus_max_recursion` setting and data quality
- **State timeline gaps**: Ensure events have proper `occurred_at` timestamps
- **Incremental issues**: Review `_ingested_at` values and watermark logic

## Links & References

- **Blog Post**:
  [Data Beyond Dashboards](https://www.slideruleanalytics.com/blog/dbt-nexus-data-beyond-dashboards)
- **Documentation**: `/docs/index.md`
- **Demo Data Guide**: `/docs/tutorials/demo-data.md`
- **Use Cases**: `/docs/explanations/use-cases.md`
- **Model Reference**: `/docs/reference/models/`
- **Macro Reference**: `/docs/reference/macros/`
- **State Naming Guide**: `/models/nexus-models/states/STATES.md`
- **Derived State Macro**: `/macros/states/DERIVED_STATE_MACRO.md`
- **Configuration Guide**: `/docs/getting-started/configuration.md`
- **Architecture Deep Dive**: `/docs/explanations/architecture.md`

## Real-World Applications (SlideRule Analytics)

### Operational Use Cases

- **Timeline Apps**: Complete customer context for support/sales teams
- **Daily Updates**: Automated summaries of key business events
- **Email Marketing**: Up-to-date customer lists and segmentation
- **Abandoned Setup Notifications**: Automated onboarding outreach
- **AI Integration**: Complete customer context for AI tools
- **Metrics & Dashboards**: Consistent business metrics across all tools

### Business Value

- Faster customer support (complete context in one view)
- Higher sales conversion (full customer timeline)
- Reduced churn (proactive engagement based on events)
- Operational flexibility (add/change tools without rebuilding integrations)
