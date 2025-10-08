---
title: Development Data Filtering
tags: [how-to, development, performance, best-practices]
summary:
  Guide for limiting data volume in development environments using
  timestamp-based filtering to improve build performance while maintaining data
  integrity.
---

# Development Data Filtering

When working with large datasets spanning years or decades of data, development
builds can become slow and expensive. The `limit_by_timestamp` macro provides a
clean, maintainable way to filter data by timestamp in development environments
while keeping full datasets in production.

## The Problem

Large source datasets create challenges in development:

- **Slow builds**: Processing decades of data for every test run
- **High costs**: Expensive warehouse compute for development iterations
- **Poor developer experience**: 7+ minute builds become 20-second builds with
  filtering
- **Unnecessary data**: Most development work only needs recent data

## The Solution: `limit_by_timestamp` Macro

The `limit_by_timestamp` macro provides environment-aware timestamp filtering
that:

- ✅ Filters by actual dates (e.g., `2024-01-01`) not relative time windows
- ✅ Configurable per environment (dev, prod, or custom targets)
- ✅ Override-able per model when needed
- ✅ Cross-database compatible (Snowflake, BigQuery, Postgres, etc.)
- ✅ Cascades automatically through joins and downstream models
- ✅ Maintains data integrity and relationships

## Configuration

### Basic Setup

Add timestamp limits to your `dbt_project.yml`:

```yaml
vars:
  # Development data limiting
  dev_timestamp_limit: "2024-01-01" # Only data from 2024 onwards in dev
  prod_timestamp_limit: "2019-01-01" # Optional: limit prod data if needed
```

### Environment Targets

The macro automatically detects your environment:

- `dev` or `development` targets → uses `dev_timestamp_limit`
- `prod` or `production` targets → uses `prod_timestamp_limit`
- Other targets → no filtering (returns `true`)

If a limit variable is not set for an environment, no filtering occurs.

## Usage Patterns

### 1. Filter at the Event Level (Recommended)

Apply the filter in **intermediate layer event models** where you have clean,
normalized timestamps:

```sql
-- intermediate/source_order_events.sql
{{ config(tags=['identity-resolution', 'events'], materialized='table') }}

with orders as (
    select * from {{ ref('source_orders') }}
    where {{ nexus.limit_by_timestamp('order_date') }}  -- 👈 Filter here
),

order_events as (
    select
        {{ nexus.create_nexus_id('event', ['order_id', 'order_date']) }} as event_id,
        order_date as occurred_at,
        'order' as event_type,
        'order_placed' as event_name,
        'source' as source,
        -- ... other fields
    from orders
)

select * from order_events
```

### 2. Multiple Event Types from Same Source

Filter once at the source CTE:

```sql
-- intermediate/source_customer_events.sql
with customers as (
    select * from {{ ref('source_customers') }}
    where {{ nexus.limit_by_timestamp('created_at') }}  -- 👈 Filter once
),

signup_events as (
    select
        created_at as occurred_at,
        'signup' as event_name,
        -- ... fields
    from customers
    where created_at is not null
),

profile_update_events as (
    select
        updated_at as occurred_at,
        'profile_updated' as event_name,
        -- ... fields
    from customers
    where updated_at is not null
)

select * from signup_events
union all
select * from profile_update_events
```

### 3. Custom Column Names

Override the default `occurred_at` column:

```sql
where {{ nexus.limit_by_timestamp('enrollment_date') }}
```

```sql
where {{ nexus.limit_by_timestamp('first_seen_at') }}
```

### 4. Per-Model Overrides

Override the global limit for specific models:

```sql
-- This model needs only the last year in dev
where {{ nexus.limit_by_timestamp('occurred_at', dev_limit='2024-01-01') }}
```

```sql
-- This model needs more history in dev but less in prod
where {{ nexus.limit_by_timestamp('occurred_at', dev_limit='2022-01-01', prod_limit='2020-01-01') }}
```

## Automatic Cascade Effect

The beauty of filtering at the event level is that it **cascades automatically**
through your entire pipeline:

```text
✅ Events (filtered)
    ↓
✅ Person Identifiers (inherits filter via ref)
    ↓
✅ Person Traits (inherits filter via ref)
    ↓
✅ Group Identifiers (inherits filter via ref)
    ↓
✅ Group Traits (inherits filter via ref)
    ↓
✅ Unioned Models (inherits filter via union)
    ↓
✅ Identity Resolution (processes filtered data)
```

### Example Cascade

```sql
-- intermediate/source_order_events.sql
with orders as (
    select * from {{ ref('source_orders') }}
    where {{ nexus.limit_by_timestamp('order_date') }}  -- ✅ Filter applied
)
-- ... event logic

-- intermediate/source_order_person_identifiers.sql
{{ nexus.unpivot_identifiers(
    model_name='source_order_events',  -- ✅ Already filtered!
    -- ... config
) }}

-- intermediate/source_order_person_traits.sql
{{ nexus.unpivot_traits(
    model_name='source_order_events',  -- ✅ Already filtered!
    -- ... config
) }}

-- source_events.sql (union layer)
{{ dbt_utils.union_relations([
    ref('source_order_events'),        -- ✅ Already filtered!
    ref('source_payment_events'),      -- ✅ Already filtered!
    ref('source_support_events')       -- ✅ Already filtered!
]) }}
```

## Where to Apply Filters

### DO Apply Filters In

1. **Intermediate event models** - Where clean timestamps exist
2. **Source CTEs** - At the top of event models for single-point filtering
3. **Event-generating queries** - Before creating event records

### DON'T Apply Filters In

1. **Base layer** - Timestamps may not be cleaned/standardized yet
2. **Normalized layer** - Keep full normalization/deduplication logic intact
3. **Identifier/Trait models** - They inherit from filtered events automatically
4. **Union models** - They inherit from filtered intermediate models
5. **Identity resolution models** - They process already-filtered data

## Architecture Pattern

Following the
[recommended four-layer architecture](recommend-source-model-structure.md):

```text
Layer 1: Base (raw)              → ❌ No filter (raw data)
Layer 2: Normalized              → ❌ No filter (full normalization)
Layer 3: Intermediate (events)   → ✅ FILTER HERE
Layer 4: Unioned                 → ❌ No filter (inherits)
```

## Performance Benefits

Real-world results from filtering at the intermediate layer:

- **Before filtering**: 7+ minutes to build source models
- **After filtering**: 20 seconds to build source models
- **Speedup**: ~21x faster builds in development
- **Data integrity**: Maintained across all relationships and joins

## Join Behavior

When filtering events that are joined with other tables:

```sql
with events as (
    select * from {{ ref('source_events') }}
    where {{ nexus.limit_by_timestamp('event_date') }}  -- Small filtered dataset
),

participants as (
    select * from {{ ref('source_participants') }}
    -- Full table, but...
),

events_with_participants as (
    select
        e.*,
        p.participant_name,
        p.participant_email
    from events e                    -- ← Filtered (small)
    left join participants p         -- ← Full table (large)
        on e.participant_id = p.id
)
```

**Result**: Only participants matching the filtered events are returned. The
database optimizer handles this efficiently.

**Optional Performance Optimization**: For very large joined tables, you can
pre-filter them too:

```sql
participants as (
    select * from {{ ref('source_participants') }}
    where {{ nexus.limit_by_timestamp('created_at') }}
),
```

This is optional but may improve join performance on extremely large datasets.

## Cross-Database Compatibility

The macro uses dbt's cross-database functions:

```sql
-- Generated SQL (works across all databases)
occurred_at >= '2024-01-01'
```

This simple comparison works identically in:

- Snowflake
- BigQuery
- Postgres
- Redshift
- Databricks

## Testing Your Filters

### Verify Row Counts

```sql
-- Check event counts before/after
select
    min(occurred_at) as earliest_event,
    max(occurred_at) as latest_event,
    count(*) as total_events
from {{ ref('source_events') }}
```

### Verify Cascade

```sql
-- Ensure identifiers match filtered events
select count(distinct event_id) as unique_event_ids
from {{ ref('source_person_identifiers') }}

-- Should match event count (assuming 1:1 relationship)
select count(*) as total_events
from {{ ref('source_events') }}
```

## Troubleshooting

### Filter Not Working

**Check your target name**:

```bash
dbt run --target dev  # Should use dev_timestamp_limit
```

The macro only applies to targets named `dev`, `development`, `prod`, or
`production`.

### Different Results in Dev vs Prod

This is **expected behavior**! Dev has less data by design. To test with full
data locally:

```bash
# Option 1: Use prod target
dbt run --target prod

# Option 2: Temporarily remove the limit
dbt run --vars '{"dev_timestamp_limit": null}'

# Option 3: Override with older date
dbt run --vars '{"dev_timestamp_limit": "2019-01-01"}'
```

### Still Too Much Data

Adjust your limit to a more recent date:

```yaml
vars:
  dev_timestamp_limit: "2024-06-01" # Only last 6 months
```

## Best Practices

1. **Start conservative**: Begin with more data (2+ years) then reduce if needed
2. **One filter point**: Apply at event level, let it cascade
3. **Document limits**: Comment why you chose specific dates in
   `dbt_project.yml`
4. **Test in prod**: Periodically run with prod data to catch edge cases
5. **Monitor performance**: Track build times to verify improvements
6. **Consider data relationships**: Ensure filtered timeframe includes complete
   business cycles

## Related Documentation

- [Recommended Source Model Structure](recommend-source-model-structure.md) -
  Four-layer architecture
- [Source Tests](source-tests.md) - Testing strategies for source models
- [Create Source Models](create-source-models.md) - Step-by-step source creation
  guide
