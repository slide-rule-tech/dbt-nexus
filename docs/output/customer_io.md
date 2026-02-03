# Customer.io Integration

This document describes how to generate Customer.io-compatible output for syncing
**people** (Identify), **events** (Track), **objects** (Group), and
**relationships** (Group with userId) via the Snowflake Reverse ETL integration.

## Overview

| Sync Type                | Model                            | Source                          |
| ------------------------ | -------------------------------- | ------------------------------- |
| Identify (people)        | `customer_io_persons`            | `nexus_entities` (person)       |
| Track (events)           | `customer_io_events`             | `nexus_events`                  |
| Group (objects)          | `customer_io_<object_type>`      | `nexus_entities` (group)        |
| Group (relationships)    | `customer_io_<object>_relationships` | `nexus_relationships`       |

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

---

# Objects (Group Sync)

Customer.io supports
[custom objects](https://docs.customer.io/journeys/objects/) that represent
non-person entities like companies, locations, accounts, or products. Objects
can be related to people, enabling powerful segmentation like "people associated
with location X" or "people whose primary account is Y".

## Prerequisites: Create Object Type in Customer.io

Before syncing objects, create an object type in Customer.io:

1. Go to **Data & Integrations** → **Objects**
2. Click **Create object type**
3. Configure the object type:
   - **Name**: e.g., `Location`, `Account`, `Company`
   - **Singular**: e.g., `location`
   - **Plural**: e.g., `locations`
   - **ID attribute**: e.g., `location_id`
4. Click **Create**
5. Note the **Object Type ID** (visible in URL or settings) - you'll need this
   for your dbt model

## Required Columns

| Column         | Description                                           |
| -------------- | ----------------------------------------------------- |
| `groupId`      | Unique identifier for the object (required)           |
| `objectTypeId` | Customer.io object type ID (required, e.g., `'1'`)    |
| `timestamp`    | When the object was last updated                      |

All additional columns become object attributes (traits).

## Example: Location Objects

```sql
-- models/output/customer_io/customer_io_locations.sql
{{ config(materialized='view') }}

with locations as (
    select
        entity_id,
        location_id,
        location_name,
        location_lobbie_integration_uuid,
        _updated_at,
        _created_at
    from {{ ref('nexus_entities') }}
    where entity_type = 'group'
      and location_id is not null
)

select
    -- Customer.io Group sync required fields
    location_id as "groupId",
    '1' as "objectTypeId",  -- Your object type ID from Customer.io
    to_timestamp_ntz(_updated_at) as "timestamp",
    
    -- Object traits (stored as attributes on the location)
    location_name as "location_name",
    location_lobbie_integration_uuid as "location_lobbie_integration_uuid",
    entity_id as "nexus_entity_id",
    to_timestamp_ntz(_created_at) as "created_at"
    
from locations
order by "timestamp" desc
```

## Reverse ETL Query

```sql
SELECT *
FROM YOUR_SCHEMA.customer_io_locations
WHERE TO_TIMESTAMP_NTZ("timestamp") > TO_TIMESTAMP_NTZ({{last_sync_time}})
```

## Customer.io Setup

1. Go to **Data & Integrations** → **Integrations** → **Snowflake**
2. Click **Add Sync**
3. Select **Group** as the sync type
4. Configure column mappings:
   - **Object ID**: `groupId`
   - **Object Type ID**: `objectTypeId`
   - **User ID**: *Leave empty* (creates objects without relationships)
   - **Timestamp**: `timestamp`
5. Map additional columns as object attributes
6. Enable the sync

---

# Relationships (Group Sync with userId)

Relationships connect people to objects. When you include a `userId` in a Group
sync, Customer.io creates (or updates) the relationship between that person and
the object.

## Relationship Attributes

Customer.io supports storing attributes on the *relationship* itself, not just
on the object. This is powerful for modeling things like:

- "Is this the person's primary location?"
- "When did they first interact with this location?"
- "What is their role in this account?"

**Important**: Relationship attributes must be passed as a JSON object in a
column named `relationshipAttributes`. Regular columns are stored on the object,
not the relationship.

## Required Columns

| Column                   | Description                                        |
| ------------------------ | -------------------------------------------------- |
| `groupId`                | Object identifier (required)                       |
| `objectTypeId`           | Customer.io object type ID (required)              |
| `userId`                 | Person identifier - email (required for relationships) |
| `timestamp`              | When the relationship was last updated             |
| `relationshipAttributes` | JSON object with relationship-specific attributes  |

## Example: Person-Location Relationships

This model creates relationships between patients and the locations they've
visited, with attributes like `is_primary_location` and `first_interaction_at`:

```sql
-- models/output/customer_io/customer_io_location_relationships.sql
{{ config(materialized='view') }}

-- Only include relationships for persons in customer_io_persons
with customer_io_person_ids as (
    select "userId" as email
    from {{ ref('customer_io_persons') }}
),

-- Get all person-location relationships with stats
relationship_stats as (
    select
        r.relationship_id,
        r.entity_a_id as person_id,
        r.entity_b_id as group_id,
        g.location_id,
        g.location_name,
        p.email,
        r.established_at as first_interaction_at,
        r.last_updated_at as last_interaction_at,
        r._updated_at
    from {{ ref('nexus_relationships') }} r
    inner join {{ ref('nexus_entities') }} p 
        on r.entity_a_id = p.entity_id
        and p.entity_type = 'person'
    inner join {{ ref('nexus_entities') }} g 
        on r.entity_b_id = g.entity_id
        and g.entity_type = 'group'
    inner join customer_io_person_ids cip
        on p.email = cip.email
    where r.relationship_type = 'membership'
      and r.entity_a_type = 'person'
      and r.entity_b_type = 'group'
      and g.location_id is not null
      and p.email is not null
),

-- Rank locations for each person
ranked_relationships as (
    select
        *,
        row_number() over (
            partition by person_id 
            order by last_interaction_at desc
        ) as rank_by_recency,
        row_number() over (
            partition by person_id 
            order by first_interaction_at asc
        ) as rank_by_first,
        count(*) over (partition by person_id) as location_count
    from relationship_stats
),

final as (
    select
        -- Customer.io Group sync required fields
        location_id as "groupId",
        '1' as "objectTypeId",
        email as "userId",
        to_timestamp_ntz(_updated_at) as "timestamp",
        
        -- Relationship attributes as JSON object
        -- See: https://docs.customer.io/integrations/data-in/connections/reverse-etl/snowflake/#relationship-attributes
        object_construct(
            'is_primary_location', case when rank_by_recency = 1 then true else false end,
            'is_most_recent_location', case when rank_by_recency = 1 then true else false end,
            'is_first_location', case when rank_by_first = 1 then true else false end,
            'has_multiple_locations', case when location_count > 1 then true else false end,
            'location_count', location_count,
            'first_interaction_at', to_timestamp_ntz(first_interaction_at),
            'last_interaction_at', to_timestamp_ntz(last_interaction_at),
            'location_name', location_name
        ) as "relationshipAttributes"
        
    from ranked_relationships
)

select * from final
order by "timestamp" desc
```

## Example `relationshipAttributes` Output

```json
{
  "is_primary_location": true,
  "is_most_recent_location": true,
  "is_first_location": false,
  "has_multiple_locations": true,
  "location_count": 2,
  "first_interaction_at": "2025-01-15 10:30:00.000",
  "last_interaction_at": "2025-09-20 14:45:00.000",
  "location_name": "GameDay Mens Health - Downtown"
}
```

## Reverse ETL Query

```sql
SELECT *
FROM YOUR_SCHEMA.customer_io_location_relationships
WHERE TO_TIMESTAMP_NTZ("timestamp") > TO_TIMESTAMP_NTZ({{last_sync_time}})
```

## Customer.io Setup

1. Go to **Data & Integrations** → **Integrations** → **Snowflake**
2. Click **Add Sync**
3. Select **Group** as the sync type
4. Configure column mappings:
   - **Object ID**: `groupId`
   - **Object Type ID**: `objectTypeId`
   - **User ID**: `userId` (this creates the relationship!)
   - **Timestamp**: `timestamp`
   - **Relationship Attributes**: `relationshipAttributes`
5. Enable the sync

## Sync Order

For initial setup, run syncs in this order:

1. **Persons** first (creates people profiles)
2. **Objects** second (creates location/account/etc. objects)
3. **Relationships** third (links people to objects)
4. **Events** can run anytime after Persons

After initial setup, syncs can run in parallel.

## Segmentation Use Cases

With relationship attributes synced, you can create segments like:

- **Primary location is X**: Filter where `is_primary_location = true` for a
  specific location
- **Multi-location people**: Filter where `has_multiple_locations = true`
- **Lapsed at primary location**: Filter where `is_primary_location = true` AND
  `last_interaction_at` is more than 30 days ago
- **New at location**: Filter where `is_first_location = true` AND
  `first_interaction_at` is within the last 7 days

---

# Defining Relationship Declarations in Nexus

Before you can sync relationships to Customer.io, you need to define
relationship declarations in your source models. Nexus processes these
declarations through its identity resolution pipeline to create the final
`nexus_relationships` table.

## Enable Relationships for Your Source

In your `dbt_project.yml`, enable relationships for your source:

```yaml
vars:
  nexus:
    sources:
      your_source:
        enabled: true
        events: true
        entities: ["person", "group"]
        relationships: true  # Enable relationship processing
```

## Create Relationship Declaration Model

Create a model named `{source}_relationship_declarations.sql` in your source
folder. This model should output the following columns:

| Column                       | Description                                      |
| ---------------------------- | ------------------------------------------------ |
| `relationship_declaration_id`| Unique ID (use `nexus.create_nexus_id`)          |
| `event_id`                   | Event that established the relationship          |
| `occurred_at`                | When the relationship was established            |
| `entity_a_identifier`        | Identifier for entity A (e.g., patient_id)       |
| `entity_a_identifier_type`   | Type of identifier (e.g., `'patient_id'`)        |
| `entity_a_type`              | Entity type: `'person'` or `'group'`             |
| `entity_a_role`              | Role in relationship (e.g., `'patient'`)         |
| `entity_b_identifier`        | Identifier for entity B (e.g., location_id)      |
| `entity_b_identifier_type`   | Type of identifier (e.g., `'location_id'`)       |
| `entity_b_type`              | Entity type: `'person'` or `'group'`             |
| `entity_b_role`              | Role in relationship (e.g., `'location'`)        |
| `relationship_type`          | Type: `'membership'`, `'association'`, etc.      |
| `relationship_direction`     | Direction: `'a_to_b'`, `'b_to_a'`, `'bidirectional'` |
| `is_active`                  | Whether relationship is currently active         |
| `source`                     | Source system name                               |

## Example: Patient-Location Relationships

```sql
-- models/sources/lobbie/intermediate/lobbie_patient_location_relationship_declarations.sql
{{ config(
    materialized='table',
    tags=['event-processing', 'relationships']
) }}

with appointment_relationships as (
    select
        event_id,
        occurred_at,
        patient_id,
        location_id,
        'lobbie' as source
    from {{ ref('lobbie_appointment_events') }}
    where patient_id is not null
      and location_id is not null
),

relationship_declarations as (
    select distinct
        {{ nexus.create_nexus_id('relationship_declaration', 
            ['event_id', 'patient_id', 'location_id', "'patient'", 'occurred_at']) 
        }} as relationship_declaration_id,
        
        event_id,
        occurred_at,
        
        -- Entity A: Person (patient)
        patient_id as entity_a_identifier,
        'patient_id' as entity_a_identifier_type,
        'person' as entity_a_type,
        'patient' as entity_a_role,
        
        -- Entity B: Group (location)
        location_id as entity_b_identifier,
        'location_id' as entity_b_identifier_type,
        'group' as entity_b_type,
        'location' as entity_b_role,
        
        -- Relationship metadata
        'membership' as relationship_type,
        'a_to_b' as relationship_direction,
        true as is_active,
        source
        
    from appointment_relationships
)

select * from relationship_declarations
```

## Union Model

Create a top-level model that unions all relationship declarations for your
source:

```sql
-- models/sources/lobbie/lobbie_relationship_declarations.sql
{{ config(
    materialized='table',
    tags=['event-processing', 'relationship_declarations']
) }}

select
    relationship_declaration_id,
    event_id,
    occurred_at,
    entity_a_identifier,
    entity_a_identifier_type,
    entity_a_type,
    entity_a_role,
    entity_b_identifier,
    entity_b_identifier_type,
    entity_b_type,
    entity_b_role,
    relationship_type,
    relationship_direction,
    is_active,
    source
from {{ ref('lobbie_patient_location_relationship_declarations') }}
-- UNION ALL additional relationship types here
order by occurred_at desc
```

## Run the Pipeline

After creating your relationship declaration models:

1. Run `dbt run` to build the models
2. Nexus will process the declarations through its identity resolution pipeline
3. Final relationships appear in `nexus_relationships`
4. Use `nexus_relationships` as the source for your Customer.io relationship
   model
