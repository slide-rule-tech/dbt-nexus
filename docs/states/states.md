---
title: State Models Reference
tags: [reference, models, states, timeline]
summary:
  Complete reference for dbt-nexus state management models including naming
  conventions and best practices.
---

# State Models Reference

State models in dbt-nexus provide timeline-based state tracking for entities
with support for derived states and complex business logic.

## Overview

State models answer the question: **"What is the state of their X?"**

For example:

- "What is the state of their `billing_lifecycle`?" → `"active"`
- "What is the state of their `sliderule_app_installation`?" → `"installed"`

## Core State Model: `nexus_states`

The main state model that unions all individual state models.

### Schema

| Column             | Type      | Description                                   |
| ------------------ | --------- | --------------------------------------------- |
| `entity_id`        | string    | Unique identifier for the entity              |
| `entity_type`      | string    | Type of entity (`person`, `group`)            |
| `state_name`       | string    | Name of the state dimension                   |
| `state_value`      | string    | Current value of the state                    |
| `state_entered_at` | timestamp | When this state was entered                   |
| `state_exited_at`  | timestamp | When this state was exited (NULL for current) |
| `is_current`       | boolean   | Whether this is the current state             |
| `source`           | string    | Source system that generated this state       |
| `_ingested_at`     | timestamp | When the record was processed                 |

### Example Query

```sql
-- Get current billing status for all entities
SELECT
    entity_id,
    state_value as billing_status,
    state_entered_at
FROM {{ ref('nexus_states') }}
WHERE state_name = 'billing_lifecycle'
  AND is_current = TRUE
```

## State Naming Convention

State names follow the format: `<namespace>_<subject>[_qualifier]`

### Components

| Part        | Description                       | Examples                              |
| ----------- | --------------------------------- | ------------------------------------- |
| `namespace` | Domain or system prefix           | `sliderule`, `google`, `billing`      |
| `subject`   | Object whose state is tracked     | `app`, `profile`, `connection`        |
| `qualifier` | Lifecycle or sub-track (optional) | `installation`, `lifecycle`, `status` |

### Examples

| State Name                    | Example Values                            | Meaning                    |
| ----------------------------- | ----------------------------------------- | -------------------------- |
| `sliderule_app_installation`  | `installed`, `uninstalled`, `deactivated` | App installation state     |
| `google_analytics_connection` | `connected`, `disconnected`, `none`       | GA4 integration status     |
| `billing_lifecycle`           | `none`, `trialing`, `active`, `cancelled` | Billing subscription state |
| `onboarding_progress`         | `invited`, `started`, `completed`         | User onboarding status     |

## Individual State Models

Each state dimension should have its own model file following the naming
convention.

### File Structure

```
models/
├── states/
│   ├── nexus_states.sql           # Main union model
│   ├── billing_lifecycle.sql      # Individual state model
│   ├── sliderule_app_installation.sql
│   └── google_analytics_connection.sql
├── documentation/
│   ├── BILLING_LIFECYCLE.md       # State documentation
│   ├── SLIDERULE_APP_INSTALLATION.md
│   └── GOOGLE_ANALYTICS_CONNECTION.md
```

### Individual State Model Template

```sql
-- models/states/billing_lifecycle.sql
{{ config(
    materialized='incremental',
    unique_key='id',
    tags=['states', 'billing']
) }}

WITH events AS (
    SELECT * FROM {{ ref('nexus_events') }}
    WHERE event_name IN ('subscription_created', 'subscription_cancelled', 'trial_started')
    {% if is_incremental() %}
    AND occurred_at > (SELECT MAX(state_entered_at) FROM {{ this }})
    {% endif %}
),

state_changes AS (
    SELECT
        entity_id,
        'group' as entity_type,
        'billing_lifecycle' as state_name,
        CASE
            WHEN event_name = 'trial_started' THEN 'trialing'
            WHEN event_name = 'subscription_created' THEN 'active'
            WHEN event_name = 'subscription_cancelled' THEN 'cancelled'
        END as state_value,
        occurred_at as state_entered_at,
        source,
        _ingested_at
    FROM events
    WHERE entity_id IS NOT NULL
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['entity_id', 'state_name', 'state_entered_at']) }} as id,
    entity_id,
    entity_type,
    state_name,
    state_value,
    state_entered_at,
    LEAD(state_entered_at) OVER (
        PARTITION BY entity_id, state_name
        ORDER BY state_entered_at
    ) as state_exited_at,
    CASE
        WHEN LEAD(state_entered_at) OVER (
            PARTITION BY entity_id, state_name
            ORDER BY state_entered_at
        ) IS NULL THEN TRUE
        ELSE FALSE
    END as is_current,
    source,
    _ingested_at
FROM state_changes
```

## Derived States

Derived states combine multiple base states using the `derived_state` macro.

### Example: Active Shop Status

```sql
-- models/states/active_shop_status.sql
{{ config(
    materialized='incremental',
    unique_key='id',
    tags=['states', 'derived']
) }}

{{ derived_state(
    state_name='active_shop_status',
    component_states=[
        {
            'name': 'ga',
            'table': 'google_analytics_connection',
            'condition': "case when state_value = 'connected' then 1 else 0 end"
        },
        {
            'name': 'app',
            'table': 'sliderule_app_installation',
            'condition': "case when state_value = 'installed' then 1 else 0 end"
        }
    ],
    combination_logic="case when current_ga_status = 1 and current_app_status = 1 then 'active' else 'inactive' end"
) }}
```

## Best Practices

### Naming

- Use descriptive but concise names
- Avoid redundancy between `state_name` and `state_value`
- Use consistent `snake_case` formatting
- Be specific: prefer `billing_lifecycle` over `status`

### Implementation

- Always include the state in the main `nexus_states` union
- Use incremental materialization for performance
- Add appropriate tags for organization
- Document each state with a companion `.md` file

### Performance

- Index on `entity_id`, `state_name`, and `is_current`
- Use appropriate partitioning for time-series data
- Consider view materialization for frequently changing states

## Related Documentation

- [State Management Concepts](../../explanations/state-management.md)
- [Creating Custom States](../../how-to/create-custom-states.md)
- [Derived State Macro](../macros/state-management.md#derived_state)
- [State Naming Convention Guide](../../../models/nexus-models/states/STATES.md)
