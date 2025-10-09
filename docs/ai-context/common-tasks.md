---
title: Common Tasks
tags: [ai-context, tasks, implementation, step-by-step]
summary: Step-by-step guides for frequent implementation tasks with dbt-nexus.
---

# Common Tasks

## Setting Up a New Source

### Step 1: Configure Source in dbt_project.yml

```yaml
vars:
  nexus:
    sources:
      your_source_name:
        enabled: true
        events: true
        entities: ["person"]
        relationships: true
```

### Step 2: Create Four-Layer Architecture

#### Base Layer - Raw Tables

**`models/sources/your_source/base/base_orders.sql`**:

```sql
select * from {{ source('your_source', 'orders') }}
```

**`models/sources/your_source/base/base_customers.sql`**:

```sql
select * from {{ source('your_source', 'customers') }}
```

#### Normalized Layer - Clean Business Entities

**`models/sources/your_source/normalized/your_source_orders.sql`**:

```sql
select
    o.order_id,
    o.customer_id,
    o.order_date,
    o.total_amount,
    c.customer_name,
    c.email,
    c.phone_number
from {{ ref('base_orders') }} o
left join {{ ref('base_customers') }} c
    on o.customer_id = c.customer_id
```

#### Intermediate Layer - Event-Specific Formatting

**`models/sources/your_source/intermediate/your_source_order_events.sql`**:

```sql
{{ config(materialized='table', tags=['event-processing']) }}

select
    {{ nexus.create_nexus_id('event', ['order_id', 'order_date']) }} as event_id,
    order_date as occurred_at,
    'order' as type,
    'order_placed' as event_name,
    'Order placed for ' || total_amount as event_description,
    'your_source' as source,

    -- Source-specific fields
    customer_id,
    order_id,
    total_amount,
    customer_name,
    email,
    phone_number

from {{ ref('your_source_orders') }}
where order_date is not null
```

**`models/sources/your_source/intermediate/your_source_order_person_identifiers.sql`**:

```sql
{{ config(materialized='table', tags=['identity-resolution']) }}

{{ nexus.unpivot_identifiers(
    model_name='your_source_order_events',
    event_id_field='event_id',
    edge_id_field='event_id',
    columns=['customer_id', 'email', 'phone_number'],
    additional_columns=['occurred_at', 'source'],
    column_to_identifier_type={
        'customer_id': 'customer_id',
        'email': 'email',
        'phone_number': 'phone'
    },
    role_column="'customer'"
) }}
```

#### Unioned Layer - Combined Models

**`models/sources/your_source/your_source_events.sql`**:

```sql
{{ config(materialized='table', tags=['event-processing']) }}

{{ dbt_utils.union_relations([
    ref('your_source_order_events'),
    ref('your_source_payment_events')
]) }}

order by occurred_at desc
```

### Step 3: Test the Integration

```bash
dbt run --select source:your_source
dbt test --select source:your_source
```

## Creating Custom States

### Step 1: Create State Model

**`models/states/billing_lifecycle.sql`**:

```sql
select
    person_id,
    'trial' as state,
    trial_started_at as state_entered_at,
    trial_ended_at as state_exited_at,
    case when trial_ended_at is null then true else false end as is_current
from {{ ref('billing_events') }}
where trial_started_at is not null

union all

select
    person_id,
    'paid' as state,
    subscription_started_at as state_entered_at,
    subscription_ended_at as state_exited_at,
    case when subscription_ended_at is null then true else false end as is_current
from {{ ref('billing_events') }}
where subscription_started_at is not null
```

### Step 2: Add to nexus_states Union

Update `models/nexus-models/states/nexus_states.sql`:

```sql
-- Add your new state model to the union
select * from {{ ref('billing_lifecycle') }}
```

### Step 3: Test State Model

```bash
dbt run --select billing_lifecycle
dbt run --select nexus_states
```

## Setting Up Alias Models

### Step 1: Create Final Tables Directory

```bash
mkdir -p models/final-tables/links
```

### Step 2: Create Alias Models

**`models/final-tables/persons.sql`**:

```sql
select * from {{ ref('nexus_persons') }}
```

**`models/final-tables/groups.sql`**:

```sql
select * from {{ ref('nexus_groups') }}
```

**`models/final-tables/events.sql`**:

```sql
select * from {{ ref('nexus_events') }}
```

**`models/final-tables/states.sql`**:

```sql
select * from {{ ref('nexus_states') }}
```

### Step 3: Create Link Aliases

**`models/final-tables/links/memberships.sql`**:

```sql
select * from {{ ref('nexus_memberships') }}
```

**`models/final-tables/links/person_identifiers.sql`**:

```sql
select * from {{ ref('nexus_person_identifiers') }}
```

## Configuring Schema Organization

### Step 1: Update dbt_project.yml

```yaml
models:
  your_project_name:
    final-tables:
      +schema: nexus_final_tables
    sources:
      +schema: nexus_sources
      +tags: ["nexus"]

  nexus:
    nexus-models:
      final-tables:
        +schema: nexus_final_tables
      states:
        +schema: nexus_final_tables
      identity-resolution:
        +schema: nexus_identity_resolution
      event-log:
        +schema: nexus_event_log
        nexus_events:
          +schema: nexus_final_tables
```

### Step 2: Test Configuration

```bash
dbt run --select package:nexus
dbt docs generate
```

## Running Demo Data

### Step 1: Build Demo Data

```bash
# From your dbt project directory
dbt build
```

### Step 2: Explore Demo Data

```sql
-- View all demo events
SELECT * FROM nexus_demo_data.nexus_events
ORDER BY occurred_at DESC;

-- View resolved persons
SELECT * FROM nexus_demo_data.nexus_persons;

-- View group memberships
SELECT
    p.name as person_name,
    g.name as group_name,
    m.role
FROM nexus_demo_data.nexus_memberships m
JOIN nexus_demo_data.nexus_persons p ON m.person_id = p.id
JOIN nexus_demo_data.nexus_groups g ON m.group_id = g.id;
```

## Debugging Identity Resolution

### Step 1: Check Edge Creation

```sql
-- View identity edges
SELECT * FROM nexus_identity_resolution.nexus_person_identifiers_edges
ORDER BY created_at DESC;
```

### Step 2: Verify Recursion Settings

```yaml
# Check your dbt_project.yml
vars:
  nexus_max_recursion: 5 # Adjust if needed
```

### Step 3: Test with Smaller Dataset

```bash
# Run with specific source
dbt run --select source:your_source
dbt run --select package:nexus --models tag:identity-resolution
```

## Performance Optimization

### Step 1: Adjust Recursion Depth

```yaml
vars:
  nexus_max_recursion: 3 # Reduce for better performance
```

### Step 2: Configure Incremental Models

```yaml
models:
  nexus:
    nexus-models:
      event-log:
        +materialized: incremental
        +incremental_strategy: merge
```

### Step 3: Add Partitioning (BigQuery)

```yaml
models:
  nexus:
    nexus-models:
      event-log:
        +partition_by:
          field: occurred_at
          data_type: timestamp
          granularity: day
```

## Testing Your Implementation

### Step 1: Run All Models

```bash
dbt run
dbt test
```

### Step 2: Generate Documentation

```bash
dbt docs generate
dbt docs serve
```

### Step 3: Verify Data Quality

```sql
-- Check for duplicate persons
SELECT
    email,
    COUNT(*) as count
FROM nexus_final_tables.nexus_persons
GROUP BY email
HAVING COUNT(*) > 1;

-- Check event timeline
SELECT
    MIN(occurred_at) as earliest_event,
    MAX(occurred_at) as latest_event,
    COUNT(*) as total_events
FROM nexus_final_tables.nexus_events;
```
