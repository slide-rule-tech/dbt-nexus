# Gadget Sources Documentation

This document describes how to add new data sources from Gadget to the CRM
warehouse, following the patterns established for `shopify_shops` and
`google_connections`.

## Overview

Gadget sources follow a specific pattern:

- Raw data comes from BigQuery tables with JSON records
- Base models extract and transform fields from JSON
- Existing identifier and trait models are extended using nexus macros
- **Events and memberships are unified across all Gadget sources**

## Adding a New Gadget Table

### Step 1: Update Source Definition

Add the new table to `gadget.yml`:

```yaml
sources:
  - name: gadget
    database: sliderule-analytics
    schema: gadget
    tables:
      - name: shopify_shops
      - name: google_connections
      - name: your_new_table # Add here
```

### Step 2: Create Base Model

Create a base model in `base/gadget_{table_name}_base.sql`:

```sql
{{ config(
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

with source_data as (
    select
        {{ dbt_utils.generate_surrogate_key(['id']) }} as event_id,
        'your_event_name' as event_name,
        PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', JSON_EXTRACT_SCALAR(record, '$.createdAt')) as occurred_at,

        -- Extract relevant fields from JSON record
        JSON_EXTRACT_SCALAR(record, '$.id') as record_id,
        JSON_EXTRACT_SCALAR(record, '$.emailAddress') as email_field,
        -- Add other fields as needed

        -- Keep the original record for reference
        record as raw_record,
        synced_at
    from {{ source('gadget', 'your_table_name') }}
    {{ real_time_event_filter('id') }}
),

with_latest_events as (
    {{ get_first_or_last_row(
        source='source_data',
        partition_by='record_id',  -- Use appropriate unique identifier
        order_by='occurred_at',
        column_label='is_latest',
        get='last'
    ) }}
),

deduped_events as (
    select *
    from with_latest_events
    where is_latest
)

select
    *,
    'gadget' as source,
from deduped_events
order by occurred_at desc
```

### Step 3: Update Existing Models

#### Person Identifiers (`gadget_person_identifiers.sql`)

If your table contains person identifiers (email, phone, etc.), add them:

```sql
-- Add new CTE for your table
your_table_identifiers AS (
    {{ nexus.unpivot_identifiers(
        model_name='gadget_your_table_base',
        columns=['email_field', 'phone_field'],  -- Person identifier columns
        additional_columns=["'gadget' as source", "occurred_at"],
        row_id_field="event_id",
        column_to_identifier_type={
            'email_field': 'email',
            'phone_field': 'phone'
        }
    ) }}
),

-- Add to the union
unioned AS (
    SELECT * FROM shops_identifiers
    UNION ALL
    SELECT * FROM connections_identifiers
    UNION ALL
    SELECT * FROM your_table_identifiers  -- Add here
)
```

#### Group Identifiers (`gadget_group_identifiers.sql`)

If your table contains group identifiers (shop_id, domain, etc.), add them:

```sql
-- Add new CTE for your table
your_table_identifiers AS (
    {{ nexus.unpivot_identifiers(
        model_name='gadget_your_table_base',
        columns=['shop_id', 'domain_field'],  -- Group identifier columns
        additional_columns=["'gadget' as source", "occurred_at"],
        row_id_field="event_id",
        column_to_identifier_type={
            'shop_id': 'shop_id',
            'domain_field': 'domain'
        }
    ) }}
),

-- Add to the union
unioned AS (
    SELECT * FROM shops_identifiers
    UNION ALL
    SELECT * FROM connections_identifiers
    UNION ALL
    SELECT * FROM your_table_identifiers  -- Add here
)
```

#### Person Traits (`gadget_person_traits.sql`)

If your table contains person attributes, add them:

```sql
your_table_traits AS (
    {{ nexus.unpivot_traits(
        model_name='gadget_your_table_base',
        columns=['email_field', 'name_field'],  -- Person trait columns
        identifier_column='email_field',        -- How to identify the person
        identifier_type='email',
        additional_columns=["'gadget' as source", "occurred_at"],
        column_to_trait_name={
            'email_field': 'email',
            'name_field': 'name'
        }
    ) }}
),

-- Add to the union
unioned AS (
    SELECT * FROM shops_traits
    UNION ALL
    SELECT * FROM connections_traits
    UNION ALL
    SELECT * FROM your_table_traits  -- Add here
)
```

#### Group Traits (`gadget_group_traits.sql`)

If your table contains group attributes, add them:

```sql
your_table_traits AS (
    {{ nexus.unpivot_traits(
        model_name='gadget_your_table_base',
        columns=['attribute1', 'attribute2'],   -- Group trait columns
        identifier_column='shop_id',            -- How to identify the group
        identifier_type='shop_id',
        additional_columns=["'gadget' as source", "occurred_at"],
        column_to_trait_name={
            'attribute1': 'custom_name_1',
            'attribute2': 'custom_name_2'
        }
    ) }}
),

-- Add to the union
unioned AS (
    SELECT * FROM shops_traits
    UNION ALL
    SELECT * FROM shops_additional_traits
    UNION ALL
    SELECT * FROM connections_traits
    UNION ALL
    SELECT * FROM your_table_traits  -- Add here
)
```

### Events (`gadget_events.sql`)

All Gadget event sources should be included in the unified `gadget_events.sql`
model. Each event source (e.g., shops, google connections) should have a CTE
that outputs the same columns, in the same order and types. Use `NULL` for
fields that do not apply to a given event type.

**Example pattern:**

```sql
WITH shop_events AS (
    SELECT
        event_id,
        occurred_at,
        event_name,
        event_description,
        event_value,
        value_unit,
        event_type,
        source,
        source_table,
        synced_at,
        oauth_connection_id,
        connection_email,
        needs_reconnect
    FROM ...
),

connection_events AS (
    SELECT
        event_id,
        occurred_at,
        event_name,
        event_description,
        event_value,
        value_unit,
        event_type,
        source,
        source_table,
        synced_at,
        oauth_connection_id,
        connection_email,
        needs_reconnect
    FROM ...
)

SELECT * FROM shop_events
UNION ALL
SELECT * FROM connection_events
ORDER BY occurred_at desc
```

- **Important:** All SELECTs in the union must have the same columns, in the
  same order and with compatible types. Use `cast(NULL as type)` for fields that
  do not apply to a given event type.
- Add a new CTE and union branch for each new Gadget event source.

### Membership Identifiers (`gadget_membership_identifiers.sql`)

All Gadget membership relationships should be included in the unified
`gadget_membership_identifiers.sql` model. Each source (e.g., shops, google
connections) should have a CTE that outputs the same columns, in the same order
and types. Use `NULL` for fields that do not apply to a given membership type.

**Example pattern:**

```sql
WITH shop_memberships AS (
    SELECT
        id,
        event_id,
        occurred_at,
        person_identifier,
        person_identifier_type,
        group_identifier,
        group_identifier_type,
        role,
        source
    FROM ...
),

connection_memberships AS (
    SELECT
        id,
        event_id,
        occurred_at,
        person_identifier,
        person_identifier_type,
        group_identifier,
        group_identifier_type,
        role,
        source
    FROM ...
)

SELECT * FROM shop_memberships
UNION ALL
SELECT * FROM connection_memberships
```

- **Important:** All SELECTs in the union must have the same columns, in the
  same order and with compatible types. Use `cast(NULL as type)` for fields that
  do not apply to a given membership type.
- Add a new CTE and union branch for each new Gadget membership source.

## Example: Google Connections Implementation

### Base Model Structure

- **Source**: `gadget.google_connections` table with JSON records
- **Key Fields**:
  - `emailAddress` → `email_address` (person identifier)
  - `shop` → `shop_id` (group identifier)
  - `oauthConnectionId` → `oauth_connection_id` (group trait)

### Integration Pattern

- **Person Identifiers**: Added `email_address` as `email` type
- **Group Identifiers**: Added `shop_id` and `oauth_connection_id` (as
  `myshopify_domain` type)
- **Person Traits**: Added `email_address` as `email` trait
- **Group Traits**: Added `oauth_connection_id` trait for shops
- **Events**: Added google connection creation events to unified events model
- **Membership Identifiers**: Added google connection user memberships with role
  `google_connection_user`

## Example: Google Analytics Connections Implementation

### Base Model Structure

- **Source**: `gadget.google_analytics_connections` table with JSON records
- **Key Fields**:
  - `shop` → `shop_id` (group identifier)
  - `googleConnection` → `google_connection_id` (person identifier for
    memberships)
  - `accountId` → `ga_account_id` (group identifier)
  - `propertyId` → `ga_property_id` (group identifier)
  - `measurementId` → `ga_measurement_id` (group identifier)
  - `accountName`, `propertyName`, tracking flags → event parameters

### Integration Pattern

- **Person Identifiers**: None directly (GA connections link via
  google_connection_id)
- **Group Identifiers**: Added `shop_id`, `ga_account_id`, `ga_property_id`,
  `ga_data_stream_id`, `ga_measurement_id`
- **Person Traits**: None directly
- **Group Traits**: None (since shops can have multiple GA connections)
- **Events**: Added GA connection creation events with GA4 details as event
  parameters:
  - `ga_account_name`, `ga_property_name`, `ga_data_stream_name`
  - `ga_data_stream_path`, `ga_measurement_id`
  - `use_slide_rule_tracker`, `used_for_reporting`, `used_for_tracking`
- **Membership Identifiers**: Added GA analytics user memberships linking
  google_connection_id to shop_id with role `ga_analytics_user`

**Note**: GA connection details are stored as event parameters rather than
traits because a single shop can have multiple GA connections, making traits
inappropriate for this one-to-many relationship.

## Key Principles

1. **Use nexus macros** (`unpivot_identifiers`, `unpivot_traits`) instead of
   manual UNION ALL
2. **Consistent naming**: Map source fields to standard identifier/trait names
3. **Proper typing**: Ensure consistent data types across unions
4. **Null handling**: Macros automatically filter null values
5. **Deduplication**: Use `get_first_or_last_row` for latest records only

## Notes

- Always add `'gadget' as source` to maintain source tracking
- Use `event_id` as the `row_id_field` for identifier macros
- Map JSON fields to meaningful column names in base models
- Consider which fields are identifiers vs traits vs metadata
- **Consolidated Models**: `gadget_events.sql` and
  `gadget_membership_identifiers.sql` automatically union all Gadget sources
  - Events include both shop creation and google connection creation
  - Memberships include both shop ownership and google connection relationships
