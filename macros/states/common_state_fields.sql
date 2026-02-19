{% macro common_state_fields(return_empty=false) %}
    {% if return_empty %}
        CAST(NULL AS STRING) AS state_id,
        CAST(NULL AS STRING) AS entity_id,
        CAST(NULL AS STRING) AS entity_type,
        CAST(NULL AS STRING) AS state_name,
        CAST(NULL AS STRING) AS state_value,
        CAST(NULL AS NUMERIC) AS state_numeric_value,
        CAST(NULL AS STRING) AS state_category,
        CAST(NULL AS TIMESTAMP) AS state_entered_at,
        CAST(NULL AS TIMESTAMP) AS state_exited_at,
        CAST(NULL AS BOOLEAN) AS is_current,
        CAST(NULL AS STRING) AS trigger_event_id
    {% else %}
        {{ nexus.create_nexus_id('state', ['entity_id', 'state_name', 'state_entered_at', 'trigger_event_id']) }} AS state_id,
        entity_id,
        entity_type,
        state_name,
        state_value,
        state_numeric_value,
        state_category,
        state_entered_at,
        state_exited_at,
        is_current,
        trigger_event_id
    {% endif %}
{% endmacro %}
