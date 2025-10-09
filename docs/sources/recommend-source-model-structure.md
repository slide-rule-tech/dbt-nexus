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
closely mirror the original database structure. Each table represents a single
entity from the source system (orders, customers, products, etc.) and remains
separate. Usually this involves cleaning up the ELT formatted raw tables for
deduplication, JSON extraction, aliasing, etc. Usually:

- **Explicit field selection** - No `SELECT *` to ensure schema stability
- **Mirrors source schema** - Keeps tables separate (orders separate from
  customers)
- **Consistent naming** - Standardized column names across the pipeline
- **Data type consistency** - Ensures compatible data types for downstream
  processing
- **Deduplicating data** - Deduplicate rows
- **No joins** - Joins happen in the intermediate layer, not here

**Example**:

```sql
-- source_orders.sql
select
    order_id,
    customer_id,
    order_date,
    total_amount,
    status
from {{ ref('base_source_orders') }}
qualify row_number() over (partition by order_id order by updated_at desc) = 1

-- source_customers.sql
select
    customer_id,
    customer_name,
    email,
    phone_number,
    created_at
from {{ ref('base_source_customers') }}
qualify row_number() over (partition by customer_id order by updated_at desc) = 1
```

### 3. **Intermediate Layer** - Event-Type Specific Formatting

**Purpose**: Transform normalized data into Nexus event-log formats ready for
Nexus processing. Creates intermediate models for each event type that extract
identifiers and traits for different entity types (persons, groups, etc.).

The intermediate layer contains specialized models that format data according to
specific event types (appointments, payments, orders, etc.). This is where joins
between normalized tables occur to bring together related data for each event
type. This layer:

- **Joins normalized tables** - Combines related entities (orders + customers)
  as needed for each event type
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

customers as (
    select * from {{ ref('source_customers') }}
),

orders_with_customer_data as (
    select
        o.*,
        c.customer_name,
        c.email,
        c.phone_number
    from orders o
    left join customers c on o.customer_id = c.customer_id
),

events as (
    select
        -- Nexus event standard fields
        {{ nexus.create_nexus_id('event', ['order_id', 'order_date']) }} as event_id,
        order_date as occurred_at,
        'order' as event_type,
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

    from orders_with_customer_data
    where order_date is not null
)

select * from events
```

### 4. **Unioned Layer** - Nexus-Ready Aggregations

**Purpose**: Combine all event types and entity types into final
Nexus-compatible tables

The unioned layer uses `dbt_utils.union_relations()` or simple UNION ALL to
combine intermediate models into final, production-ready tables. For the new
entity-centric architecture, this layer creates:

- `source_events` - Union of all event types
- `source_entity_identifiers` - Union of all person and group identifiers
- `source_entity_traits` - Union of all person and group traits
- `source_relationship_declarations` - All entity relationships

This approach provides:

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
    tags=['nexus', 'events', 'source']
) }}

{{ dbt_utils.union_relations([
    ref('source_order_events'),
    ref('source_payment_events'),
    ref('source_support_events')
]) }}

order by occurred_at desc

-- source_entity_identifiers.sql
{{ config(
    materialized='table',
    tags=['nexus', 'entity_identifiers', 'source']
) }}

-- Union person and group identifiers from all event types
with person_identifiers as (
    select
        {{ create_nexus_id('entity_identifier', [...]) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'person' as entity_type,
        'email' as identifier_type,
        customer_email as identifier_value,
        'source' as source,
        order_date as occurred_at,
        _ingested_at,
        'customer' as role
    from {{ ref('source_order_events') }}
    where customer_email is not null
),

group_identifiers as (
    select
        {{ create_nexus_id('entity_identifier', [...]) }} as entity_identifier_id,
        event_id,
        event_id as edge_id,
        'group' as entity_type,
        'domain' as identifier_type,
        company_domain as identifier_value,
        'source' as source,
        order_date as occurred_at,
        _ingested_at,
        'organization' as role
    from {{ ref('source_order_events') }}
    where company_domain is not null
)

select * from person_identifiers
union all
select * from group_identifiers

-- source_entity_traits.sql
-- Similar structure unioning person and group traits

-- source_relationship_declarations.sql
select
    {{ create_nexus_id('relationship_declaration', [...]) }} as relationship_declaration_id,
    event_id,
    occurred_at,
    customer_email as entity_a_identifier,
    'email' as entity_a_identifier_type,
    'person' as entity_a_type,
    'customer' as entity_a_role,
    company_domain as entity_b_identifier,
    'domain' as entity_b_identifier_type,
    'group' as entity_b_type,
    'organization' as entity_b_role,
    'customer_organization' as relationship_type,
    'a_to_b' as relationship_direction,
    true as is_active,
    'source' as source
from {{ ref('source_order_events') }}
where customer_email is not null
    and company_domain is not null
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
│   ├── {source}_payment_events.sql
│   └── {source}_support_events.sql
├── {source}_events.sql                     (unions all event types)
├── {source}_entity_identifiers.sql         (unions person + group identifiers)
├── {source}_entity_traits.sql              (unions person + group traits)
└── {source}_relationship_declarations.sql  (person-group and other relationships)
```

**Note**: The intermediate layer no longer creates separate
`{event_type}_person_identifiers` and `{event_type}_group_identifiers` models.
Instead, each intermediate event model contains the logic to extract identifiers
and traits for multiple entity types, and the unioned layer combines them into
unified entity models.

## Best Practices

### **Naming Conventions**

- **Base models**: `base_{source}_{table_name}.sql`
- **Normalized models**: `{source}_{entity_name}.sql`
- **Intermediate models**: `{source}_{event_type}_events.sql`
- **Union models**:
  - `{source}_events.sql` - All events
  - `{source}_entity_identifiers.sql` - All entity identifiers (person + group)
  - `{source}_entity_traits.sql` - All entity traits (person + group)
  - `{source}_relationship_declarations.sql` - All relationships

### **Configuration**

- Use appropriate `materialized` settings (usually `table` for identity
  resolution)
- Add relevant `tags` for organization and filtering
- Include proper `ref()` statements for dependencies

### **Testing**

- Test each layer independently
- Validate data quality at each transformation step
- Ensure proper join logic in intermediate layer
- Verify Nexus macro outputs in intermediate layer

## Common Patterns

### **E-commerce Sources**

- **Base**: Raw order, customer, product tables
- **Normalized**: Clean orders and customer tables, separated (no joins)
- **Intermediate**: Order events (with orders joined to customers), payment
  events, etc.
- **Union**:
  - `source_events.sql` - All event types
  - `source_entity_identifiers.sql` - Person (customer emails) + Group (company
    domains) identifiers
  - `source_entity_traits.sql` - Person names, emails + Group company names,
    domains
  - `source_relationship_declarations.sql` - Customer-to-company relationships

### **CRM Sources**

- **Base**: Raw contact, account, activity tables
- **Normalized**: Clean contacts, accounts, and activities tables, separated (no
  joins)
- **Intermediate**: Activity events (with activities joined to contacts and
  accounts)
- **Union**:
  - `source_events.sql` - All activity types
  - `source_entity_identifiers.sql` - Person (contact emails) + Group (account
    domains) identifiers
  - `source_entity_traits.sql` - Person contact details + Group account details
  - `source_relationship_declarations.sql` - Contact-to-account relationships

### **Event Tracking Sources**

- **Base**: Raw event, user, session tables
- **Normalized**: Clean events, users, and sessions tables, separated (no joins)
- **Intermediate**: Formatted events (with events joined to users and sessions)
- **Union**:
  - `source_events.sql` - All event types (page views, tracks, etc.)
  - `source_entity_identifiers.sql` - Person (user IDs, emails, anonymous IDs)
    identifiers
  - `source_entity_traits.sql` - Person user traits
  - `source_relationship_declarations.sql` - User relationships (if applicable)

This architecture provides a solid foundation for scalable, maintainable data
pipelines that integrate seamlessly with the dbt-nexus identity resolution
system.
