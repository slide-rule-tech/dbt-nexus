---
title: Event Schema Quick Reference
tags: [reference, events, schema, quick-reference]
summary: Quick reference for nexus event schema requirements
---

# Event Schema Quick Reference

## Required Fields

| Field         | Type      | Description        | Example               |
| ------------- | --------- | ------------------ | --------------------- |
| `event_id`    | STRING    | Unique event ID    | `evt_lobbie_abc123`   |
| `occurred_at` | TIMESTAMP | Business timestamp | `2024-01-15 14:30:00` |
| `event_type`  | STRING    | Event category     | `appointment`         |
| `event_name`  | STRING    | Specific event     | `appointment booked`  |
| `source`      | STRING    | Source system      | `lobbie`              |

## Optional Fields

| Field               | Type      | Description        | Example               |
| ------------------- | --------- | ------------------ | --------------------- |
| `event_description` | STRING    | Human description  | `Appointment booked`  |
| `value`             | NUMERIC   | Numeric value      | `150.00`              |
| `value_unit`        | STRING    | Value unit         | `USD`                 |
| `significance`      | NUMERIC   | Event significance | `3`                   |
| `_ingested_at`      | TIMESTAMP | Processing time    | `2024-01-15 14:35:00` |

## Source-Specific Fields

Include source-specific fields for reference and debugging:

| Field Type            | Examples                                               |
| --------------------- | ------------------------------------------------------ |
| **Primary Keys**      | `appointment_id`, `email_id`, `transaction_id`         |
| **Entity References** | `patient_id`, `customer_id`, `user_id`                 |
| **Status Fields**     | `appointment_status`, `email_status`, `payment_status` |
| **Metadata**          | `location_id`, `department`, `priority`                |
| **Timestamps**        | `created_at`, `updated_at`, `scheduled_at`             |

## ID Generation Macro

```sql
{{ nexus.create_nexus_id('event', ['unique_cols']) }}
```

## Quick Template

```sql
select
    {{ nexus.create_nexus_id('event', ['id', 'timestamp']) }} as event_id,
    timestamp_field as occurred_at,
    'category' as event_type,
    'event name' as event_name,
    'source' as source,
    'Description' as event_description,
    null as value,
    null as value_unit,
    null as significance,
    current_timestamp() as _ingested_at,

    -- Source-specific fields (for reference)
    source_id,
    entity_id,
    status_field,
    metadata_field
from {{ ref('base_source_table') }}
where timestamp_field is not null
```

## Event Naming Conventions

### Types

- `appointment`, `communication`, `transaction`, `product`

### Names

- `appointment booked`, `email sent`, `payment completed`

## Common Issues

- **Missing event_id**: Use `create_nexus_id` macro
- **Invalid timestamp**: Cast to TIMESTAMP
- **Duplicate IDs**: Include more unique columns
- **Missing fields**: Check all required fields present
