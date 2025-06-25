# Derived State Macro

The `derived_state` macro enables easy creation of derived states that combine
multiple base states using timeline merging logic.

## Usage

```sql
{{ derived_state(
    state_name='your_state_name',
    component_states=[
        {
            'name': 'component1',
            'table': 'base_state_table_name',
            'condition': "transformation logic for this component"
        },
        {
            'name': 'component2',
            'table': 'another_base_state_table',
            'condition': "transformation logic for this component"
        }
    ],
    combination_logic="logic to combine current_component1_status and current_component2_status",
    entity_type='group'  -- optional, defaults to 'group'
) }}
```

## Parameters

- **state_name**: Name of the derived state (must match filename)
- **component_states**: Array of component state definitions
  - **name**: Short identifier for this component
  - **table**: Base state table to read from (use model name, not full ref)
  - **condition**: SQL expression to transform state_value into desired format
- **combination_logic**: SQL CASE statement that combines
  `current_{name}_status` values
- **entity_type**: Optional entity type (defaults to 'group')

## How It Works

1. **Component Collection**: Unions all component state changes into timeline
2. **Forward-Fill**: Uses window functions to determine component status at each
   timestamp
3. **Combination**: Applies your logic to compute derived status at each
   timestamp
4. **Transition Detection**: Only creates records when derived status actually
   changes
5. **Standardization**: Outputs standard state schema with proper timestamps

## Examples

### Binary AND Logic (Active Shop)

```sql
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

### Numeric Thresholds (Revenue Tiers)

```sql
{{ derived_state(
    state_name='revenue_tier',
    component_states=[
        {
            'name': 'billing',
            'table': 'billing_lifecycle',
            'condition': "case when state_value = 'active' then 1 else 0 end"
        },
        {
            'name': 'amount',
            'table': 'billing_subscription_amount',
            'condition': "cast(state_value as numeric)"
        }
    ],
    combination_logic="""
        case
            when current_billing_status = 1 and current_amount_status >= 100 then 'premium'
            when current_billing_status = 1 and current_amount_status >= 50 then 'standard'
            when current_billing_status = 1 and current_amount_status > 0 then 'basic'
            else 'none'
        end
    """
) }}
```

## Best Practices

1. **File Naming**: Derived state file name must match `state_name` parameter
2. **Tags**: Always use `tags=['states', 'derived']` in model config
3. **Documentation**: Create UPPERCASE.md file with business context and
   examples
4. **Component Names**: Use short, descriptive names (they become column
   prefixes)
5. **State Updates**: Remember to add new derived states to
   compiled-sql/states.sql union
