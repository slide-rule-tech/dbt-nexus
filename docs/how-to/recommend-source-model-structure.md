---
title: Recommended Source Model Structure
tags: [how-to, architecture, best-practices, sources]
summary:
  Four-layer data architecture pattern for transforming raw source data into
  Nexus-compatible formats with proper separation of concerns and
  maintainability.
---

# Recommended Source Model Structure

This guide outlines the recommended four-layer architecture pattern for
organizing source models in dbt-nexus projects. This structure ensures data
quality, maintainability, and scalability while providing clear separation of
concerns.

## Four-Layer Strategy Overview

This dbt project implements a sophisticated four-layer data architecture
designed to transform raw source data into a standardized Nexus-compatible
format. Each layer serves a specific purpose in the data transformation
pipeline, ensuring data quality, maintainability, and scalability.

### 1. **Base Layer** - Raw Tables

**Purpose**: Direct connection to ELTed source systems with minimal
transformation

The base layer contains simple `SELECT *` statements that pull data directly
from the raw ELTed database tables. Raw tables are often formatted for
convenient extraction and loading, with duplicates, JSON columns, etc. This
layer serves as the foundation of our data pipeline, providing:

- **Zero transformation overhead** - Fastest possible data access
- **Source system fidelity** - Preserves original data structure and types
- **Change detection** - Easy to spot schema changes in upstream systems
- **Debugging foundation** - Raw data available for troubleshooting

**Example**:

```sql
-- base_source_table1.sql
select * from RAW_SCHEMA.SOURCE_RAW.TABLE1

-- base_source_table2.sql
select * from RAW_SCHEMA.SOURCE_RAW.TABLE2
```

### 2. **Normalized Layer** - Database Replicas

**Purpose**: Clean, standardized representations of business entities

The normalized layer transforms raw data into clean, business-ready tables that
closely mirror the original database structure. Usually this involves cleaning
up the ELT formatted raw tables for deduplication, JSON extraction, aliasing,
etc. Usually:

- **Explicit field selection** - No `SELECT *` to ensure schema stability
- **Proper joins** - Combines related tables (e.g., orders + customer data)
- **Consistent naming** - Standardized column names across the pipeline
- **Data type consistency** - Ensures compatible data types for downstream
  processing
- **Deduplicating data** - deduplicate rows

**Example**:

```sql
-- source_orders.sql
select
    o.order_id,
    o.customer_id,
    o.order_date,
    o.total_amount,
    c.customer_name,
    c.email,
    c.phone_number
from {{ ref('base_source_orders') }} o
left join {{ ref('base_source_customers') }} c
    on o.customer_id = c.customer_id
```

### 3. **Intermediate Layer** - Event-Type Specific Formatting

**Purpose**: Transform normalized data into Nexus event-log formats ready for
Nexus processing. Creates the following models for each event type when
relevant:

- events
- person_identifiers
- person_traits
- group_identifiers
- group_traits
- membership_identifiers

The intermediate layer contains specialized models that format data according to
specific event types (appointments, payments, orders, etc.). This layer:

- **Separates concerns** - Each event type has its own processing logic
- **Enables independent development** - Teams can work on different event types
  without conflicts
- **Supports Nexus macros** - Uses `nexus.unpivot_identifiers()` and
  `nexus.unpivot_traits()` to create standardized event structures
- **Maintains data lineage** - Clear traceability from source to final output
- **Union relations** - Makes it easy to union relations in union models with
  different columns.

**Key Nexus Macros Used**:

- `nexus.unpivot_identifiers()` - Extracts and standardizes identifier fields
- `nexus.unpivot_traits()` - Extracts and standardizes trait/attribute fields
- `nexus.create_nexus_id()` - Generates consistent, deterministic IDs

**Example**:

```sql
-- source_order_events.sql
{{ config(
    materialized='table',
    tags=['event-processing']
) }}

with orders as (
    select * from {{ ref('source_orders') }}
),

events as (
    select
        -- Nexus event standard fields
        {{ nexus.create_nexus_id('event', ['order_id', 'order_date'], 'source') }} as event_id,
        order_date as occurred_at,
        'order' as type,
        'order_placed' as event_name,
        'Order placed for ' || total_amount as event_description,
        'source' as source,

        -- Source-specific fields
        customer_id,
        order_id,
        total_amount,
        customer_name,
        email,
        phone_number

    from orders
    where order_date is not null
)

select * from events
```

### 4. **Unioned Layer** - Nexus-Ready Aggregations

**Purpose**: Combine all event types into final Nexus-compatible tables

The unioned layer uses `dbt_utils.union_relations()` to combine intermediate
models into final, production-ready tables. This approach provides:

- **Robust unioning** - `dbt_utils.union_relations()` handles schema differences
  automatically
- **Type safety** - Automatic type coercion and null handling
- **Maintainability** - Easy to add new event types by adding to the union list
- **Performance** - Optimized union operations
- **Error handling** - Better error messages and debugging capabilities

**Example**:

```sql
-- source_events.sql
{{ config(
    materialized='table',
    tags=['event-processing']
) }}

{{ dbt_utils.union_relations([
    ref('source_order_events'),
    ref('source_payment_events'),
    ref('source_support_events')
]) }}

order by occurred_at desc
```

## Why This Architecture?

### **Separation of Concerns**

Each layer has a single responsibility, making the codebase easier to
understand, test, and maintain.

### **dbt_utils.union_relations Benefits**

- **Automatic schema alignment** - Handles column order and type differences
- **Null handling** - Automatically fills missing columns with nulls
- **Type coercion** - Converts compatible types automatically
- **Better error messages** - Clear feedback when schemas are incompatible

### **Nexus Macro Integration**

- **Standardized output** - Ensures all events follow the same schema
- **Identity resolution** - Proper handling of person and group identifiers
- **Trait extraction** - Consistent attribute processing across event types
- **ID generation** - Deterministic, collision-resistant identifiers

### **Scalability**

- **Easy expansion** - Add new event types by creating intermediate models
- **Independent testing** - Each layer can be tested in isolation
- **Parallel development** - Teams can work on different event types
  simultaneously

## Directory Structure

Organize your source models following this directory structure:

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
│   ├── {source}_order_person_traits.sql
│   ├── {source}_order_group_identifiers.sql
│   └── {source}_order_group_traits.sql
└── {source}_events.sql
```

## Best Practices

### **Naming Conventions**

- **Base models**: `base_{source}_{table_name}.sql`
- **Normalized models**: `{source}_{entity_name}.sql`
- **Intermediate models**: `{source}_{event_type}_{model_type}.sql`
- **Union models**: `{source}_events.sql`, `{source}_person_identifiers.sql`,
  etc.

### **Configuration**

- Use appropriate `materialized` settings (usually `table` for identity
  resolution)
- Add relevant `tags` for organization and filtering
- Include proper `ref()` statements for dependencies

### **Testing**

- Test each layer independently
- Validate data quality at each transformation step
- Ensure proper join logic in normalized layer
- Verify Nexus macro outputs in intermediate layer

## Common Patterns

### **E-commerce Sources**

- **Base**: Raw order, customer, product tables
- **Normalized**: Clean orders with customer data joined
- **Intermediate**: Order events, customer identifiers/traits, product group
  traits
- **Union**: Combined events and identity resolution models

### **CRM Sources**

- **Base**: Raw contact, account, activity tables
- **Normalized**: Clean contacts with account data
- **Intermediate**: Activity events, contact identifiers/traits, account group
  traits
- **Union**: Combined events and identity resolution models

### **Event Tracking Sources**

- **Base**: Raw event, user, session tables
- **Normalized**: Clean events with user context
- **Intermediate**: Formatted events, user identifiers/traits
- **Union**: Combined events and identity resolution models

## Migration Strategy

When implementing this structure for existing sources:

1. **Audit current models** - Identify which layer each model belongs to
2. **Create base layer** - Extract raw table access into base models
3. **Refactor normalized** - Clean up joins and field selection
4. **Create intermediate** - Add event-type specific formatting
5. **Update unions** - Use `dbt_utils.union_relations()` for combining

This architecture provides a solid foundation for scalable, maintainable data
pipelines that integrate seamlessly with the dbt-nexus identity resolution
system.
