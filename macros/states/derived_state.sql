{% macro derived_state(
    state_name,
    component_states,
    combination_logic,
    entity_type='group'
) %}

-- Macro for creating derived states that combine multiple base states
-- Combines multiple component states using timeline merging logic

with all_component_changes as (
    {% for component in component_states %}
        {{ "UNION ALL" if not loop.first }}
        
        -- {{ component.name }} state changes
        select 
            entity_id,
            state_entered_at as timestamp,
            '{{ component.name }}' as component,
            {{ component.condition }} as is_active,
            state_value as component_state_value,
            trigger_event_id
        from {{ ref(component.table) }}
    {% endfor %}
),

-- Forward-fill component status at each timestamp
component_status_timeline as (
    select 
        entity_id,
        timestamp,
        component,
        is_active,
        component_state_value,
        trigger_event_id,
        
        -- Generate forward-fill columns for each component
        {% for component in component_states %}
        last_value(case when component = '{{ component.name }}' then is_active end ignore nulls) 
            over (partition by entity_id order by timestamp 
                  rows unbounded preceding) as current_{{ component.name }}_status{{ "," if not loop.last }}
        {% endfor %}
    from all_component_changes
),

-- Calculate combined status at each timestamp using provided logic
combined_status_timeline as (
    select 
        entity_id,
        timestamp,
        component,
        component_state_value,
        trigger_event_id,
        
        -- Apply the combination logic
        {{ combination_logic }} as combined_status
    from component_status_timeline
),

-- Identify status transitions (where combined_status actually changed)
status_transitions_raw as (
    select 
        entity_id,
        timestamp,
        combined_status,
        component,
        component_state_value,
        trigger_event_id,
        lag(combined_status) over (
            partition by entity_id order by timestamp
        ) as prev_combined_status
    from combined_status_timeline
),

-- Filter to only actual transitions
status_transitions as (
    select 
        entity_id,
        timestamp as state_entered_at,
        combined_status as state_value,
        component as trigger_component,
        component_state_value as trigger_component_value,
        trigger_event_id,
        -- Calculate when this status ends (next transition)
        lead(timestamp) over (
            partition by entity_id order by timestamp
        ) as state_exited_at
    from status_transitions_raw
    where combined_status != coalesce(prev_combined_status, 
        -- Default initial state - extract from combination_logic
        {% if 'active' in combination_logic %}
            'inactive'
        {% else %}
            'unknown'
        {% endif %}
    ) or prev_combined_status is null
),

-- Final output with standardized structure
final as (
    select 
        entity_id,
        '{{ entity_type }}' as entity_type,
        '{{ state_name }}' as state_name,
        state_value,
        state_entered_at,
        state_exited_at,
        state_exited_at is null as is_current,
        trigger_event_id
    from status_transitions
    where state_value is not null
)

select *
from final
order by state_entered_at desc

{% endmacro %} 