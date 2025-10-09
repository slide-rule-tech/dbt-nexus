# Creating Events from Normalized Status-Based Tables

## Overview

A common pattern in event-driven systems is converting normalized tables with
status columns into event-based data. This guide covers how to transform tables
like appointments, bookings, orders, or reservations into Nexus-formatted events
while maintaining data integrity.

## The Pattern

### Source Data Structure

Your normalized table typically has:

- A primary identifier (e.g., `appointment_id`, `order_id`, `booking_id`)
- A `status` column (e.g., "scheduled", "confirmed", "completed", "cancelled")
- A `created_on` timestamp (when the record was created)
- A `last_updated_on` timestamp (when the status was last changed)

### Target Event Structure

You want to generate events that capture the lifecycle:

1. **Initial Event**: Always create a "created" or "scheduled" event at the
   `created_on` timestamp
2. **Status Events**: For records that have progressed beyond the initial
   status, create an event at the `last_updated_on` timestamp

## Implementation

### Step 1: Join Your Normalized Data

Start by joining your normalized table with any necessary reference data if
needed. If not, skip:

```sql
with appointments as (
    select * from {{ ref('normalized_appointments') }}
),

locations as (
    select * from {{ ref('locations') }}
),

joined_data as (
    select
        a.*,
        l.location_name,
        l.location_id
    from appointments a
    left join locations l
        on a.location_id = l.location_id
)
```

### Step 2: Generate Initial Events

Create an event for every record at its creation timestamp:

```sql
initial_events as (
    select
        -- Generate consistent event_id (important for deduplication)
        {{ nexus.create_nexus_id('event', ['appointment_id', "'appointment scheduled'"]) }} as event_id,
        created_on as occurred_at,
        'appointment' as event_type,
        'appointment scheduled' as event_name,
        'appointment scheduled for ' || appointment_type || ' at ' || location_name as event_description,
        'your_source' as source,

        -- Optional fields
        null as value,
        null as value_unit,
        current_timestamp() as _ingested_at,

        -- Source-specific fields
        patient_id,
        appointment_id,
        appointment_type,
        start_datetime,
        location_id,
        location_name,

        -- Timestamps (keep for reference)
        created_on,
        last_updated_on

    from joined_data
    where created_on is not null
      and location_id is not null
)
```

### Step 3: Generate Status Change Events

Create events for records that have moved beyond the initial status:

```sql
status_events as (
    select
        -- Generate consistent event_id based on status
        {{ nexus.create_nexus_id('event', ['appointment_id', "'appointment ' || appointment_status"]) }} as event_id,
        last_updated_on as occurred_at,
        'appointment' as event_type,
        'appointment ' || appointment_status as event_name,
        'appointment ' || appointment_status || ' for ' || appointment_type || ' at ' || location_name as event_description,
        'your_source' as source,

        -- Optional fields
        null as value,
        null as value_unit,
        current_timestamp() as _ingested_at,

        -- Source-specific fields
        patient_id,
        appointment_id,
        appointment_type,
        start_datetime,
        location_id,
        location_name,

        -- Timestamps
        created_on,
        last_updated_on

    from joined_data
    where appointment_status != 'scheduled'  -- CRITICAL: Avoid duplicating initial events
      and last_updated_on is not null
      and location_id is not null
)
```

### Step 4: Union the Event Sets

Combine both event types:

```sql
select * from initial_events
union all
select * from status_events
order by occurred_at desc
```

## Critical Considerations

### 1. Avoiding Duplicate Initial Events

**The Problem**: If you don't filter out the initial status in `status_events`,
you'll create duplicate events for records that are still in their initial
state.

**The Solution**: Always exclude the initial status from your status events CTE:

```sql
where appointment_status != 'scheduled'  -- or 'created', 'pending', etc.
```

### 2. Consistent Event ID Generation

**Why It Matters**: Consistent event IDs allow you to detect true duplicates and
ensure idempotency in your data pipeline.

**Best Practice**: Use the same fields in the same order for event_id
generation:

```sql
-- Initial events
{{ nexus.create_nexus_id('event', ['record_id', "'initial_status_name'"]) }}

-- Status events
{{ nexus.create_nexus_id('event', ['record_id', "'prefix ' || status_column"]) }}
```

**Don't Include Timestamps**: Notice we don't include `created_on` or
`last_updated_on` in the event_id generation. This ensures that if the same
status appears multiple times, you generate the same event_id, making duplicates
detectable. If there are true duplicates in the underlying normalized data, fix
that in normalization.

### 3. Timestamp Selection

- **Initial Events**: Always use `created_on` for `occurred_at`
- **Status Events**: Always use `last_updated_on` for `occurred_at`

This ensures chronological accuracy and allows you to track when each status
change actually occurred.

## Complete Example

```sql
{{ config(
    materialized='table',
    tags=['event-processing']
) }}

with orders as (
    select * from {{ ref('normalized_orders') }}
),

customers as (
    select * from {{ ref('customers') }}
),

joined_data as (
    select
        o.*,
        c.customer_name,
        c.customer_email
    from orders o
    left join customers c on o.customer_id = c.customer_id
),

-- Always generate an initial "order placed" event
initial_events as (
    select
        {{ nexus.create_nexus_id('event', ['order_id', "'order placed'"]) }} as event_id,
        created_on as occurred_at,
        'order' as event_type,
        'order placed' as event_name,
        'order placed for ' || customer_name as event_description,
        'ecommerce' as source,

        null as value,
        null as value_unit,
        current_timestamp() as _ingested_at,

        order_id,
        customer_id,
        customer_name,
        order_total,
        created_on,
        last_updated_on

    from joined_data
    where created_on is not null
      and customer_id is not null
),

-- Generate current status events (excluding initial status)
status_events as (
    select
        {{ nexus.create_nexus_id('event', ['order_id', "'order ' || order_status"]) }} as event_id,
        last_updated_on as occurred_at,
        'order' as event_type,
        'order ' || order_status as event_name,
        'order ' || order_status || ' for ' || customer_name as event_description,
        'ecommerce' as source,

        null as value,
        null as value_unit,
        current_timestamp() as _ingested_at,

        order_id,
        customer_id,
        customer_name,
        order_total,
        created_on,
        last_updated_on

    from joined_data
    where order_status != 'placed'  -- Avoid duplicating initial events
      and last_updated_on is not null
      and customer_id is not null
)

select * from initial_events
union all
select * from status_events
```

## Testing Your Implementation

### Create a Data Quality Test

Create a test file in your `tests/` directory (e.g., `test_order_events.sql`):

```sql
-- Test to validate order_events logic
-- This test ensures:
-- 1. Orders with "placed" status only have exactly 1 event
-- 2. Orders with non-placed status have exactly 2 events (placed + current status)
-- 3. No orders have more than 2 events
-- The test PASSES if it returns 0 rows (no violations found)

with latest_status as (
    select
        order_id,
        max(case when event_name != 'order placed' then event_name end) as current_status_event
    from {{ ref('order_events') }}
    group by order_id
),

event_counts as (
    select
        order_id,
        count(*) as event_count
    from {{ ref('order_events') }}
    group by order_id
),

validation as (
    select
        ec.order_id,
        ec.event_count,
        ls.current_status_event,
        case
            -- Initial status should have exactly 1 event
            when ls.current_status_event is null and ec.event_count != 1 then
                'FAIL: Initial order has ' || ec.event_count || ' events instead of 1'
            -- Non-initial status should have exactly 2 events
            when ls.current_status_event is not null and ec.event_count != 2 then
                'FAIL: ' || ls.current_status_event || ' order has ' || ec.event_count || ' events instead of 2'
            else null
        end as failure_reason
    from event_counts ec
    join latest_status ls on ec.order_id = ls.order_id
)

-- Return only rows with failures (test passes when 0 rows returned)
select
    order_id,
    event_count,
    current_status_event,
    failure_reason
from validation
where failure_reason is not null
```

### Run Your Test

```bash
# Run specific test
dbt test --select test_order_events

# Run all tests
dbt test
```

### Validation Queries

Use these queries to manually verify your implementation:

**Check event counts by status:**

```sql
select
    event_name,
    count(*) as count,
    count(distinct event_id) as distinct_events,
    case when count(*) != count(distinct event_id)
         then 'HAS DUPLICATES'
         else 'NO DUPLICATES'
    end as duplicate_check
from order_events
group by event_name
order by count desc
```

**Verify timestamp usage:**

```sql
select
    order_id,
    event_name,
    occurred_at,
    created_on,
    last_updated_on,
    case
        when event_name = 'order placed' then
            case when occurred_at = created_on then 'CORRECT' else 'WRONG' end
        else
            case when occurred_at = last_updated_on then 'CORRECT' else 'WRONG' end
    end as timestamp_check
from order_events
where order_id in (
    select order_id
    from order_events
    group by order_id
    having count(*) = 2
    limit 10
)
order by order_id, occurred_at
```

**Check event distribution:**

```sql
select
    'Total Records' as metric,
    count(distinct order_id) as value
from order_events

union all

select
    'Records with Initial Status Only',
    count(*)
from (
    select order_id
    from order_events
    group by order_id
    having count(*) = 1
)

union all

select
    'Records with Status Changes',
    count(*)
from (
    select order_id
    from order_events
    group by order_id
    having count(*) = 2
)

union all

select
    'Records with Anomalies (>2 events)',
    count(*)
from (
    select order_id
    from order_events
    group by order_id
    having count(*) > 2
)
```

## Common Pitfalls

### ❌ Including Timestamps in Event ID

```sql
-- DON'T DO THIS
{{ nexus.create_nexus_id('event', ['order_id', 'created_on', "'order placed'"]) }}
```

This creates unique event_ids even for duplicate events, making it impossible to
detect duplicates.

### ❌ Not Filtering Initial Status

```sql
-- DON'T DO THIS
status_events as (
    select ...
    from joined_data
    -- Missing: where order_status != 'placed'
)
```

This creates duplicate events for records still in their initial state.

### ❌ Using Same Timestamp for Both Event Types

```sql
-- DON'T DO THIS
initial_events as (
    select
        last_updated_on as occurred_at,  -- WRONG: should be created_on
        ...
)
```

This loses the true chronology of when events occurred.

## Expected Results

For a properly implemented pattern:

- **Records in initial status**: 1 event (initial event only)
- **Records that have changed status**: 2 events (initial + current status)
- **No duplicates**: Each record should have at most 2 events
- **Correct timestamps**: Initial events use `created_on`, status events use
  `last_updated_on`
- **Chronological order**: Events should be ordered by `occurred_at`

## Summary

This pattern provides a robust way to convert status-based normalized tables
into event-based data while:

1. ✅ Maintaining complete event history
2. ✅ Avoiding duplicate events
3. ✅ Preserving timestamp accuracy
4. ✅ Enabling data quality testing
5. ✅ Supporting idempotent pipelines

By following this pattern, you ensure consistent, reliable event data across all
your normalized tables.
