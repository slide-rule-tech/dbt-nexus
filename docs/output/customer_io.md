# Customer.io Integration

This document describes how to generate Customer.io-compatible output for syncing
**people** (Identify) and **events** (Track) via the Snowflake Reverse ETL integration.

## Overview

| Sync Type         | Model                 | Source                                   |
| ----------------- | --------------------- | ---------------------------------------- |
| Identify (people) | `customer_io_persons` | `nexus_entities` (person)                |
| Track (events)    | `customer_io_events`  | `nexus_events` (filtered by source/type) |

---

# People (Identify Sync)

The `customer_io_identify` macro generates a table formatted for Customer.io's
[Reverse ETL Snowflake integration](https://docs.customer.io/integrations/data-in/connections/reverse-etl/snowflake/#identify).
It automatically discovers all trait columns from `nexus_entities`, applies
proper timestamp formatting, and handles deduplication.

## Quick Start

```sql
-- models/output/customer_io.sql
{{ config(materialized='table') }}

{{ nexus.customer_io_identify(
    entity_type='person',
    user_id_column='user_id',
    anonymous_id_column='segment_anonymous_id',
    dedupe_column='email',
    filters=[
        "email IS NOT NULL",
        "status = 'active'"
    ]
) }}
```

## Parameters

| Parameter            | Type   | Default      | Description                                              |
| -------------------- | ------ | ------------ | -------------------------------------------------------- |
| `entity_type`        | string | `'person'`   | Entity type to select from nexus_entities                |
| `user_id_column`     | string | `'user_id'`  | Column to use as Customer.io userId                      |
| `anonymous_id_column`| string | `none`       | Column to use as anonymousId (optional)                  |
| `dedupe_column`      | string | `'email'`    | Column to deduplicate by (lowercased/trimmed)            |
| `ignore_traits`      | list   | `[]`         | Trait column names to exclude from output                |
| `rename_traits`      | dict   | `{}`         | Map of `original_name` -> `new_name` for renaming        |
| `filters`            | list   | `[]`         | Additional WHERE clause conditions                       |

## Output Format

The macro generates a table with the following structure:

| Column        | Description                                          |
| ------------- | ---------------------------------------------------- |
| `userId`      | Customer.io user identifier (from `user_id_column`)  |
| `anonymousId` | Anonymous identifier (if `anonymous_id_column` set)  |
| `timestamp`   | When to apply the identify (from `_updated_at`)      |
| `"trait_name"`| All other columns as quoted traits for Snowflake     |

## Features

### Automatic Column Discovery

The macro uses `adapter.get_columns_in_relation()` to discover all columns from
`nexus_entities` at compile time. This means:

- New traits added to your entities are automatically included
- No need to manually list every trait column
- Use `ignore_traits` to exclude columns you don't want

### Default Renames for Customer.io Reserved Traits

The macro automatically renames certain columns to match Customer.io's reserved
trait names:

| Nexus Column   | Customer.io Trait | Description                           |
| -------------- | ----------------- | ------------------------------------- |
| `_created_at`  | `created_at`      | Date the user's account was created   |

You can override these defaults via `rename_traits`.

### Timestamp Transformation

Columns with timestamp types (`TIMESTAMP_NTZ`, `TIMESTAMP_LTZ`, `TIMESTAMP_TZ`,
`DATE`, `DATETIME`) are automatically wrapped with `TO_TIMESTAMP_NTZ()` for
proper Customer.io formatting.

### Deduplication

The macro deduplicates by the `dedupe_column` (default: `email`), keeping the
most recently updated record:

```sql
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY LOWER(TRIM("email")) 
    ORDER BY "timestamp" DESC NULLS LAST
) = 1
```

### Snowflake Compatibility

All trait columns are quoted (`"trait_name"`) to ensure Snowflake compatibility
with mixed-case and special character column names.

## System Columns

The following columns are automatically excluded from trait output:

- `entity_id` - Internal nexus identifier
- `entity_type` - Used for filtering, not a trait
- `_processed_at` - Internal processing timestamp
- `traits_entity_id` - Internal join column

## Examples

### Basic Usage

Sync all persons with an email:

```sql
{{ nexus.customer_io_identify(
    entity_type='person',
    user_id_column='user_id',
    filters=["email IS NOT NULL"]
) }}
```

### With Anonymous ID

Include Segment anonymous IDs for anonymous user tracking:

```sql
{{ nexus.customer_io_identify(
    entity_type='person',
    user_id_column='user_id',
    anonymous_id_column='segment_anonymous_id',
    filters=["email IS NOT NULL"]
) }}
```

### Excluding Traits

Exclude internal or debug traits:

```sql
{{ nexus.customer_io_identify(
    entity_type='person',
    user_id_column='user_id',
    ignore_traits=[
        'internal_score',
        'debug_flag',
        'test_variant'
    ],
    filters=["email IS NOT NULL"]
) }}
```

### Renaming Traits

Rename traits to match Customer.io attribute naming conventions:

```sql
{{ nexus.customer_io_identify(
    entity_type='person',
    user_id_column='user_id',
    rename_traits={
        'first_name': 'firstName',
        'last_name': 'lastName',
        'phone_number': 'phone'
    },
    filters=["email IS NOT NULL"]
) }}
```

### Filtering by Customer Journey and Adding Custom Traits

Filter to only paying customers and add customer journey state as a trait:

```sql
{{ config(materialized='view') }}

-- Only include persons who have reached "paying customer" state
with paying_customers as (
    select distinct entity_id
    from {{ ref('high_level_customer_journey') }}
    where state_value != 'lead'
),

current_journey_state as (
    select
        e.email,
        hlcj.state_value
    from {{ ref('high_level_customer_journey') }} hlcj
    inner join {{ ref('nexus_entities') }} e
        on hlcj.entity_id = e.entity_id
    where hlcj.is_current = true
),

persons as (
{{ nexus.customer_io_identify(
    entity_type='person',
    user_id_column='email',
    anonymous_id_column='segment_anonymous_id',
    dedupe_column='email',
    ignore_traits=[
        'location_lobbie_integration_uuid',
        'location_name',
        'location_id',
        'facebook_pixel_id',
        'facebook_access_key',
        'google_ads_account_id',
        'facebook_account_id'
    ],
    filters=[
        "email IS NOT NULL",
        "entity_id IN (SELECT entity_id FROM paying_customers)"
    ]
) }}
),

persons_with_state as (
    select
        p.*,
        cjs.state_value as "customer_journey_state"
    from persons p
    left join current_journey_state cjs
        on p."userId" = cjs.email
)

select * from persons_with_state
order by "timestamp" desc
```

## Setting Up Customer.io Reverse ETL

Follow these steps to sync data from your Snowflake warehouse to Customer.io.

### 1. Connect to Snowflake

1. In Customer.io, go to **Data & Integrations > Integrations**
2. Click **Directory** tab
3. Search for "Snowflake" and select **Snowflake (Data in)**
4. Enter your Snowflake credentials (account, warehouse, database, schema, user,
   private key)
5. Click **Connect**

### 2. Create Your Sync

1. Go to **Integrations > Snowflake > Syncs**
2. Click **Add Sync**
3. Select your database
4. Choose the type of data to sync (usually **Identify** for People or **Group**
   for Groups)

### 3. Define Your Query

Enter the following query, replacing `YOUR_PRODUCTION_SCHEMA` with your actual
schema name:

```sql
SELECT *
FROM YOUR_PRODUCTION_SCHEMA.customer_io
WHERE TO_TIMESTAMP_NTZ("_updated_at") > TO_TIMESTAMP_NTZ({{last_sync_time}})
```

### 4. Test Your Query

1. Click **Run Query** to preview results
2. Verify all column names are lowercase
3. Ensure you have valid email addresses
4. For initial testing, add `LIMIT 10` and run in a development environment

### 5. Enable the Sync

1. Set your sync frequency (e.g., every 15 minutes, hourly)
2. Click **Enable** to start syncing

### Important Notes

- **First sync**: On the first sync, `{{last_sync_time}}` is `0`, so all records
  will be synced
- **Subsequent syncs**: Only records updated since the last sync will be sent
- **Updating existing syncs**: When modifying an existing sync, the
  `{{last_sync_time}}` filter may cause zero changes to be detected. To resolve
  this:
  - Run once without the WHERE clause, OR
  - Create a new sync instead of modifying the existing one

## Troubleshooting

### Empty Output

If the model produces no rows, check:

1. The `entity_type` filter matches your data
2. The `user_id_column` or `anonymous_id_column` has non-null values
3. Your custom `filters` aren't too restrictive

### Missing Columns

If expected traits are missing:

1. Verify the column exists in `nexus_entities`
2. Check it's not in the `ignore_traits` list
3. Ensure it's not a system column

### Duplicate Records

If you see duplicates after sync:

1. Verify the `dedupe_column` is correct
2. Check for null values in the dedupe column (these won't deduplicate)
3. Consider adding a filter to exclude null dedupe values

---

# Events (Track Sync)

For tracking events in Customer.io, create a model that outputs data formatted
for Customer.io's
[Track sync](https://docs.customer.io/integrations/data-in/connections/reverse-etl/snowflake/#track).
Each row represents one event to be tracked against a person.

## Required Columns

| Column        | Description                                                    |
| ------------- | -------------------------------------------------------------- |
| `userId`      | Email or user identifier (required for Track)                  |
| `anonymousId` | Segment anonymous ID (optional, alternative to userId)         |
| `timestamp`   | When the event occurred (use `TO_TIMESTAMP_NTZ()`)             |
| `event`       | Event name (e.g. `appointment scheduled`, `payment completed`) |

## Event Properties

All additional columns become event properties in Customer.io. Common properties:

| Column              | Description                         |
| ------------------- | ----------------------------------- |
| `event_type`        | Event category (e.g. `appointment`, `transaction`) |
| `value`             | Numeric value (e.g. payment amount) |
| `value_unit`        | Currency or unit (e.g. `USD`)       |
| `event_data_source` | Source system (e.g. `lobbie`)       |

### Source-Specific Properties

Include relevant properties from your source system. For example, appointment
events might include:

| Column                     | Description                              |
| -------------------------- | ---------------------------------------- |
| `appointment_id`           | Unique appointment identifier            |
| `appointment_type`         | Type of appointment                      |
| `appointment_start_datetime` | Scheduled start time                   |
| `appointment_end_datetime` | Scheduled end time                       |
| `appointment_number`       | Nth appointment for this person          |
| `location_id`              | Location identifier                      |
| `location_name`            | Location display name                    |

Payment events might include:

| Column           | Description                                     |
| ---------------- | ----------------------------------------------- |
| `payment_number` | Nth payment for this person                     |
| `product_name`   | Product or service purchased                    |
| `cost`           | Payment amount                                  |
| `contract_id`    | Contract ID (for recurring payments)            |
| `is_recurring`   | Boolean flag for recurring payment              |
| `payment_date`   | Date payment was processed                      |

## Example Model

```sql
-- models/output/customer_io/customer_io_events.sql
{{ config(materialized='view') }}

-- Only include events for persons already in customer_io_persons
with customer_io_person_ids as (
    select "userId" as email
    from {{ ref('customer_io_persons') }}
),

source_events as (
    select
        e.event_id,
        e.occurred_at,
        e.event_name,
        e.event_type,
        e.value,
        e.value_unit,
        e.source
    from {{ ref('nexus_events') }} e
    where e.source = 'your_source'
),

person_participants as (
    select event_id, entity_id as person_entity_id
    from {{ ref('nexus_entity_participants') }}
    where entity_type = 'person'
),

persons as (
    select e.entity_id, e.email, e.segment_anonymous_id
    from {{ ref('nexus_entities') }} e
    inner join customer_io_person_ids cip on e.email = cip.email
    where e.entity_type = 'person'
),

events_with_person as (
    select
        se.*,
        p.email,
        p.segment_anonymous_id
    from source_events se
    inner join person_participants pp on se.event_id = pp.event_id
    inner join persons p on pp.person_entity_id = p.entity_id
    where p.email is not null
)

select
    email as "userId",
    segment_anonymous_id as "anonymousId",
    to_timestamp_ntz(occurred_at) as "timestamp",
    event_name as "event",
    event_type as "event_type",
    value as "value",
    value_unit as "value_unit",
    source as "event_data_source"
from events_with_person
order by "timestamp" desc
```

## Reverse ETL Query

Use this query in Customer.io, replacing `YOUR_SCHEMA` with your actual schema:

```sql
SELECT *
FROM YOUR_SCHEMA.customer_io_events
WHERE TO_TIMESTAMP_NTZ("timestamp") > TO_TIMESTAMP_NTZ({{last_sync_time}})
```

## Best Practices

- Use a **Track** sync type (not Identify) when setting up the sync in
  Customer.io
- Filter events to only include persons who exist in your `customer_io_persons`
  model to avoid orphaned events
- Use `{{last_sync_time}}` to avoid duplicate traffic and improve performance
- Event syncs only ingest events after `last_sync_time`; backfilling requires a
  separate one-off sync without the WHERE clause
- Quote column names (`"columnName"`) for Snowflake compatibility
- Use `TO_TIMESTAMP_NTZ()` for all timestamp columns
