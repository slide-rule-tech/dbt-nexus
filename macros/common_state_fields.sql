{% macro common_state_fields(return_empty=false) %}
    {% if return_empty %}
        CAST(NULL AS STRING) AS state_id,
        CAST(NULL AS STRING) AS entity_id,
        CAST(NULL AS STRING) AS entity_type,
        CAST(NULL AS STRING) AS state_name,
        CAST(NULL AS STRING) AS state_value,
        CAST(NULL AS TIMESTAMP) AS state_entered_at,
        CAST(NULL AS TIMESTAMP) AS state_exited_at,
        CAST(NULL AS BOOLEAN) AS is_current,
        CAST(NULL AS STRING) AS trigger_event_id
    {% else %}
        -- State identification
        {{ create_nexus_id('state', ['entity_id', 'entity_type', 'state_name', 'state_value', 'state_entered_at']) }} AS state_id,
        -- Entity identification
        entity_id,
        entity_type,
        -- State details
        state_name,
        state_value,
        -- Timestamps
        state_entered_at,
        state_exited_at,
        -- State metadata
        is_current,
        -- Event reference
        trigger_event_id
    {% endif %}
{% endmacro %} 