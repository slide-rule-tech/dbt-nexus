---
title: How to Format Events for dbt-nexus
tags: [how-to, events, nexus, formatting, schema]
summary: Complete guide for formatting events to work with the dbt-nexus package
---

# How to Format Events for dbt-nexus

This guide explains how to format events properly for the dbt-nexus package,
ensuring they integrate seamlessly with the identity resolution and event
processing pipeline.

## Overview

Events in dbt-nexus are the foundation of the identity resolution system. They
capture timestamped actions and occurrences that generate identifiers, traits,
and relationship data. Proper formatting is essential for the nexus system to
process and resolve identities correctly.

## Required Event Schema

All events must follow the standard nexus event schema with these required
fields:

### Core Fields

| Field         | Type      | Required | Description                                  | Example                                                 |
| ------------- | --------- | -------- | -------------------------------------------- | ------------------------------------------------------- |
| `event_id`    | STRING    | ✅       | Unique event identifier                      | `evt_lobbie_abc123`                                     |
| `occurred_at` | TIMESTAMP | ✅       | When the event occurred (business timestamp) | `2024-01-15 14:30:00`                                   |
| `type`        | STRING    | ✅       | Event category/type                          | `appointment`, `communication`, `transaction`           |
| `event_name`  | STRING    | ✅       | Specific event name                          | `appointment booked`, `email sent`, `payment completed` |
| `source`      | STRING    | ✅       | Source system name                           | `lobbie`, `gmail`, `stripe`                             |

### Optional Fields

| Field               | Type      | Required | Description                   | Example                               |
| ------------------- | --------- | -------- | ----------------------------- | ------------------------------------- |
| `event_description` | STRING    | ❌       | Human-readable description    | `Appointment booked in Lobbie system` |
| `value`             | NUMERIC   | ❌       | Numeric value (if applicable) | `150.00`, `5`                         |
| `value_unit`        | STRING    | ❌       | Unit of the value field       | `USD`, `count`, `hours`               |
| `_ingested_at`      | TIMESTAMP | ❌       | When dbt processed the record | `2024-01-15 14:35:00`                 |

### Source-Specific Fields

While not part of the standard nexus schema, you should include source-specific
fields for reference and debugging. These fields help with:

- **Data lineage**: Tracking back to original source records
- **Debugging**: Investigating issues with specific events
- **Business logic**: Accessing source-specific attributes for analysis

Common source-specific fields include:

| Field Type            | Description                        | Examples                                               |
| --------------------- | ---------------------------------- | ------------------------------------------------------ |
| **Primary Keys**      | Original source record identifiers | `appointment_id`, `email_id`, `transaction_id`         |
| **Entity References** | Related entity identifiers         | `patient_id`, `customer_id`, `user_id`                 |
| **Status Fields**     | Current state or status            | `appointment_status`, `email_status`, `payment_status` |
| **Metadata**          | Additional context or attributes   | `location_id`, `department`, `priority`                |
| **Timestamps**        | Additional time-related fields     | `created_at`, `updated_at`, `scheduled_at`             |

**Example source-specific fields:**

```sql
-- Source-specific fields (for reference)
appointment_id,
appointment_type,
patient_id,
appointment_status,
location_id,
start_datetime,
end_datetime,
date_of_birth,
created_by,
updated_at
```

## Event ID Generation

Use the `create_nexus_id` macro to generate proper event IDs:

```sql
{{ nexus.create_nexus_id('event', ['source_id', 'occurred_at'], 'source_name') }} as event_id
```

### Parameters:

- **Type**: Always `'event'` for events
- **Columns**: Array of columns that uniquely identify the event
- **Source**: Source system name (e.g., `'lobbie'`, `'gmail'`)

### Example:

```sql
{{ nexus.create_nexus_id('event', ['appointment_id', 'start_datetime'], 'lobbie') }} as event_id
```

This generates IDs like: `evt_lobbie_abc123def456`

## Complete Event Model Template

Here's a complete template for creating nexus-formatted events:

```sql
-- Nexus formatted events for [Source System]
-- Uses [timestamp_field] as the occurred_at timestamp
-- Follows nexus event schema pattern

with source_data as (
    select * from {{ ref('base_[source]_[entity]') }}
),

formatted_events as (
    select
        -- Required nexus event fields
        {{ nexus.create_nexus_id('event', ['unique_id', 'timestamp_field'], '[source_name]') }} as event_id,
        [timestamp_field] as occurred_at,
        '[event_category]' as type,
        '[event name]' as event_name,
        '[source_name]' as source,

        -- Optional fields
        '[Human-readable description]' as event_description,
        [numeric_value] as value,
        '[unit]' as value_unit,
        current_timestamp() as _ingested_at,

        -- Source-specific fields (for reference)
        [field1],
        [field2],
        [field3]

    from source_data
    where [timestamp_field] is not null
      and [other_conditions]
)

select * from formatted_events
order by occurred_at desc
```

## Real-World Example: Lobbie Appointments

Here's how we formatted Lobbie appointment events:

```sql
-- Nexus formatted events for Lobbie appointments
-- Uses start_datetime as the occurred_at timestamp
-- Follows nexus event schema pattern

with appointments as (
    select * from {{ ref('base_lobbie_appointments') }}
),

appointment_events as (
    select
        -- Nexus event standard fields
        {{ nexus.create_nexus_id('event', ['appointment_id', 'start_datetime'], 'lobbie') }} as event_id,
        start_datetime as occurred_at,
        'appointment' as type,
        'appointment booked' as event_name,
        'Appointment booked in Lobbie system' as event_description,
        'lobbie' as source,

        -- Optional fields
        null as value,
        null as value_unit,
        current_timestamp() as _ingested_at,

        -- Source-specific fields (for reference)
        appointment_id,
        appointment_type,
        patient_id,
        appointment_status,
        location_id,
        start_datetime,
        end_datetime,
        date_of_birth

    from appointments
    where start_datetime is not null
)

select * from appointment_events
order by occurred_at desc
```

## Event Naming Conventions

### Event Types

Use descriptive, hierarchical naming for event types:

- **Communication**: `communication`, `email`, `phone`, `chat`
- **Transactions**: `transaction`, `payment`, `purchase`, `refund`
- **Product Usage**: `product`, `feature`, `login`, `session`
- **Appointments**: `appointment`, `meeting`, `consultation`

### Event Names

Use "Object Action" format for specific events:

- `appointment booked`
- `email sent`
- `payment completed`
- `user registered`
- `support ticket created`

## Best Practices

### 1. Use Business Timestamps

Always use business timestamps for `occurred_at`, not system processing times:

```sql
-- ✅ Good: Use business timestamp
start_datetime as occurred_at

-- ❌ Avoid: System timestamp
current_timestamp() as occurred_at
```

### 2. Include Meaningful Descriptions

Provide human-readable descriptions for better context:

```sql
'Appointment booked in Lobbie system for patient consultation' as description
```

### 3. Filter Out Invalid Records

Always filter out records with missing timestamps:

```sql
where occurred_at is not null
  and occurred_at > '1900-01-01'  -- Filter out invalid dates
```

### 4. Preserve Source Fields

Keep source-specific fields for reference and debugging:

```sql
-- Source-specific fields (for reference)
appointment_id,
patient_id,
location_id,
appointment_status
```

### 5. Use Consistent Source Names

Use consistent, lowercase source names:

```sql
-- ✅ Good
'lobbie' as source

-- ❌ Avoid
'Lobbie' as source
'LOBBIE' as source
'lobbie_system' as source
```

## Testing Your Events

### 1. Compile and Run

```bash
dbt compile --select your_event_model
dbt run --select your_event_model
```

### 2. Verify Schema

Check that your events follow the required schema:

```sql
-- Verify required fields exist
SELECT
    COUNT(*) as total_events,
    COUNT(event_id) as events_with_event_id,
    COUNT(occurred_at) as events_with_timestamp,
    COUNT(type) as events_with_type,
    COUNT(event_name) as events_with_event_name,
    COUNT(source) as events_with_source
FROM your_schema.your_event_model;
```

### 3. Check Data Quality

Ensure data quality and consistency:

```sql
-- Check for duplicate event IDs
SELECT event_id, COUNT(*)
FROM your_schema.your_event_model
GROUP BY event_id
HAVING COUNT(*) > 1;

-- Check timestamp ranges
SELECT
    MIN(occurred_at) as earliest_event,
    MAX(occurred_at) as latest_event,
    COUNT(*) as total_events
FROM your_schema.your_event_model;
```

## Integration with Identity Resolution

Once your events are properly formatted, they will automatically integrate with
the nexus identity resolution system:

1. **Event Processing**: Events are processed by the nexus event log models
2. **Identifier Extraction**: Person and group identifiers are extracted from
   events
3. **Identity Resolution**: Identities are resolved across multiple sources
4. **Final Tables**: Resolved entities appear in the final nexus tables

## Common Issues and Solutions

### Issue: "create_nexus_id is undefined"

**Solution**: Ensure the nexus package is properly installed:

```bash
dbt deps
```

### Issue: Invalid timestamp format

**Solution**: Cast timestamps to proper format:

```sql
CAST(timestamp_field AS TIMESTAMP) as occurred_at
```

### Issue: Duplicate event IDs

**Solution**: Include more unique columns in the ID generation:

```sql
{{ nexus.create_nexus_id('event', ['id', 'timestamp', 'source_id'], 'source') }}
```

### Issue: Missing required fields

**Solution**: Verify all required fields are included and non-null:

```sql
WHERE occurred_at IS NOT NULL
  AND type IS NOT NULL
  AND event_name IS NOT NULL
  AND source IS NOT NULL
```

## Next Steps

After formatting your events:

1. **Create Person Identifiers**: Extract person identifiers from your events
2. **Create Group Identifiers**: Extract group identifiers if applicable
3. **Create Traits**: Extract person and group traits
4. **Test Integration**: Run the full nexus pipeline
5. **Monitor Quality**: Set up data quality tests

## Related Documentation

- [Database Schema Reference](../reference/database-schema.md)
- [Creating Source Models](./create-source-models.md)
- [Identity Resolution Configuration](./configure-identity-resolution.md)
- [dbt-nexus Package Documentation](https://github.com/sliderule-analytics/dbt-nexus)
