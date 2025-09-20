---
title: How to Generate Nexus IDs
tags: [how-to, ids, nexus, macros, create_nexus_id]
summary:
  Complete guide for generating unique IDs using the create_nexus_id macro
---

# How to Generate Nexus IDs

This guide explains how to use the `create_nexus_id` macro to generate unique,
consistent identifiers for all entities in the dbt-nexus package.

## Overview

The `create_nexus_id` macro generates standardized, unique identifiers for
different types of entities in the Nexus system. These IDs follow a consistent
pattern and include source system information for better traceability.

## ID Format

Nexus IDs follow different patterns depending on the entity type:

**Events** (with source):

```text
{prefix}_{source}_{hash}
```

**All other entities** (without source):

```text
{prefix}_{hash}
```

Where:

- **prefix**: Entity type prefix (e.g., `evt`, `per`, `grp`)
- **source**: Source system name (only for events)
- **hash**: Surrogate key generated from unique columns

## Supported Entity Types

The macro supports the following entity types with their corresponding prefixes:

| Entity Type          | Prefix     | Example (with source) | Example (without source)        |
| -------------------- | ---------- | --------------------- | ------------------------------- |
| `event`              | `evt`      | `evt_lobbie_abc123`   | N/A (events always have source) |
| `person`             | `per`      | N/A (no source)       | `per_def456`                    |
| `group`              | `grp`      | N/A (no source)       | `grp_ghi789`                    |
| `membership`         | `mem`      | N/A (no source)       | `mem_jkl012`                    |
| `state`              | `st`       | N/A (no source)       | `st_mno345`                     |
| `person_identifier`  | `per_idfr` | N/A (no source)       | `per_idfr_pqr678`               |
| `group_identifier`   | `grp_idfr` | N/A (no source)       | `grp_idfr_stu901`               |
| `person_trait`       | `per_tr`   | N/A (no source)       | `per_tr_vwx234`                 |
| `group_trait`        | `grp_tr`   | N/A (no source)       | `grp_tr_yza567`                 |
| `person_edge`        | `per_edg`  | N/A (no source)       | `per_edg_bcd890`                |
| `group_edge`         | `grp_edg`  | N/A (no source)       | `grp_edg_efg123`                |
| `person_participant` | `per_prt`  | N/A (no source)       | `per_prt_hij456`                |
| `group_participant`  | `grp_prt`  | N/A (no source)       | `grp_prt_klm789`                |
| `nexus`              | `nx`       | N/A (no source)       | `nx_nop012`                     |

## Basic Usage

### Syntax

```sql
{{ nexus.create_nexus_id(type, columns, source) }}
```

### Parameters

- **`type`** (string): Entity type (see supported types above)
- **`columns`** (array): Array of columns that uniquely identify the entity
- **`source`** (string, optional): Source system name (only used for events)

### Examples

#### Event IDs

```sql
-- Basic event ID
{{ nexus.create_nexus_id('event', ['appointment_id', 'start_datetime'], 'lobbie') }}
-- Result: evt_lobbie_abc123def456

-- Event ID without source
{{ nexus.create_nexus_id('event', ['id', 'timestamp']) }}
-- Result: evt_xyz789
```

#### Person IDs

```sql
-- Person ID from email (no source)
{{ nexus.create_nexus_id('person', ['email']) }}
-- Result: per_def456

-- Person ID from multiple identifiers (no source)
{{ nexus.create_nexus_id('person', ['user_id', 'email']) }}
-- Result: per_ghi789jkl012
```

#### Group IDs

```sql
-- Group ID from domain (no source)
{{ nexus.create_nexus_id('group', ['domain']) }}
-- Result: grp_mno345

-- Group ID from multiple fields (no source)
{{ nexus.create_nexus_id('group', ['shop_id', 'myshopify_domain']) }}
-- Result: grp_pqr678stu901
```

## Real-World Examples

### 1. Event Model

```sql
-- Nexus formatted events for Lobbie appointments
select
    {{ nexus.create_nexus_id('event', ['appointment_id', 'start_datetime'], 'lobbie') }} as event_id,
    start_datetime as occurred_at,
    'appointment' as type,
    'appointment booked' as event_name,
    'lobbie' as source,
    -- ... other fields
from {{ ref('base_lobbie_appointments') }}
where start_datetime is not null
```

### 2. Person Identifiers Model

```sql
-- Person identifiers from events (no source in ID)
select
    {{ nexus.create_nexus_id('person_identifier', ['patient_id']) }} as id,
    event_id,
    patient_id as identifier_value,
    'patient_id' as identifier_type,
    'lobbie' as source
from {{ ref('lobbie_events') }}
where patient_id is not null
```

### 3. Group Identifiers Model

```sql
-- Group identifiers from events (no source in ID)
select
    {{ nexus.create_nexus_id('group_identifier', ['domain']) }} as id,
    event_id,
    domain as identifier_value,
    'domain' as identifier_type,
    'gmail' as source
from {{ ref('gmail_events') }}
where domain is not null
```

## Best Practices

### 1. Choose Meaningful Columns

Select columns that uniquely identify the entity:

```sql
-- ✅ Good: Use unique business identifiers
{{ nexus.create_nexus_id('event', ['appointment_id', 'start_datetime'], 'lobbie') }}

-- ❌ Avoid: Using non-unique columns
{{ nexus.create_nexus_id('event', ['appointment_type'], 'lobbie') }}
```

### 2. Include Source System (Events Only)

Always include the source system for events, but not for other entity types:

```sql
-- ✅ Good: Include source for events
{{ nexus.create_nexus_id('event', ['appointment_id', 'start_datetime'], 'lobbie') }}

-- ✅ Good: No source for other entities
{{ nexus.create_nexus_id('person', ['email']) }}

-- ❌ Avoid: Including source for non-events
{{ nexus.create_nexus_id('person', ['email'], 'gmail') }}
```

### 3. Use Consistent Source Names (Events Only)

Use consistent, lowercase source names for events:

```sql
-- ✅ Good: Consistent naming for events
{{ nexus.create_nexus_id('event', ['id', 'timestamp'], 'lobbie') }}
{{ nexus.create_nexus_id('event', ['id', 'timestamp'], 'gmail') }}
{{ nexus.create_nexus_id('event', ['id', 'timestamp'], 'shopify') }}

-- ❌ Avoid: Inconsistent naming
{{ nexus.create_nexus_id('event', ['id', 'timestamp'], 'Lobbie') }}
{{ nexus.create_nexus_id('event', ['id', 'timestamp'], 'Gmail') }}
{{ nexus.create_nexus_id('event', ['id', 'timestamp'], 'Shopify_Partner') }}
```

### 4. Handle Null Values

Ensure columns used in ID generation are not null:

```sql
-- ✅ Good: Filter out nulls
{{ nexus.create_nexus_id('person', ['email'], 'gmail') }}
from {{ ref('gmail_events') }}
where email is not null

-- ❌ Avoid: Including null values
{{ nexus.create_nexus_id('person', ['email'], 'gmail') }}
from {{ ref('gmail_events') }}
-- No null check
```

## Advanced Usage

### Custom Entity Types

For custom entity types, the macro will use the first 3 characters as the
prefix:

```sql
-- Custom entity type
{{ nexus.create_nexus_id('custom', ['id'], 'system') }}
-- Result: cus_system_abc123
```

### Multiple Column Combinations

Use multiple columns to ensure uniqueness:

```sql
-- Multiple columns for uniqueness (events with source)
{{ nexus.create_nexus_id('event', ['id', 'timestamp', 'source_id'], 'system') }}
-- Result: evt_system_def456ghi789

-- Multiple columns for uniqueness (other entities without source)
{{ nexus.create_nexus_id('person', ['id', 'email', 'phone']) }}
-- Result: per_def456ghi789
```

### Conditional ID Generation

Use conditional logic for different ID patterns:

```sql
-- Conditional ID generation
case
    when source = 'lobbie' then
        {{ nexus.create_nexus_id('event', ['appointment_id', 'start_datetime'], 'lobbie') }}
    when source = 'gmail' then
        {{ nexus.create_nexus_id('event', ['message_id', 'date'], 'gmail') }}
    else
        {{ nexus.create_nexus_id('event', ['id', 'timestamp'], source) }}
end as event_id
```

## Troubleshooting

### Common Issues

#### Issue: "create_nexus_id is undefined"

**Solution**: Ensure the nexus package is properly installed:

```bash
dbt deps
```

#### Issue: Duplicate IDs

**Solution**: Include more unique columns or check for data quality issues:

```sql
-- Add more unique columns for events
{{ nexus.create_nexus_id('event', ['id', 'timestamp', 'source_id'], 'system') }}

-- Add more unique columns for other entities
{{ nexus.create_nexus_id('person', ['id', 'email', 'phone']) }}

-- Check for duplicates
select event_id, count(*)
from your_events_table
group by event_id
having count(*) > 1
```

#### Issue: Null values in ID generation

**Solution**: Filter out null values before ID generation:

```sql
-- Filter nulls
{{ nexus.create_nexus_id('person', ['email']) }}
from {{ ref('gmail_events') }}
where email is not null
  and email != ''
```

#### Issue: Inconsistent source names

**Solution**: Use consistent source naming:

```sql
-- Standardize source names
case
    when source_system = 'Lobbie' then 'lobbie'
    when source_system = 'Gmail' then 'gmail'
    else lower(source_system)
end as source
```

## Testing Your IDs

### 1. Verify Uniqueness

```sql
-- Check for duplicate IDs
select event_id, count(*)
from your_events_table
group by event_id
having count(*) > 1
```

### 2. Check ID Format

```sql
-- Verify ID format
select
    event_id,
    case
        when event_id like 'evt_%' then 'Valid event ID'
        else 'Invalid event ID'
    end as id_status
from your_events_table
```

### 3. Validate Source Consistency

```sql
-- Check source consistency
select
    source,
    count(*) as count,
    count(distinct left(event_id, length('evt_' || source || '_'))) as unique_prefixes
from your_events_table
group by source
```

## Related Documentation

- [Event Schema Quick Reference](../reference/event-schema-quick-reference.md)
- [How to Format Events](./format-nexus-events.md)
- [Database Schema Reference](../reference/database-schema.md)
- [dbt-nexus Package Documentation](https://github.com/sliderule-analytics/dbt-nexus)
