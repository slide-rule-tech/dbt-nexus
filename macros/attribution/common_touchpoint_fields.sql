{% macro common_touchpoint_fields(return_empty=false) %}
    {% if return_empty %}
        CAST(NULL AS STRING) AS touchpoint_id,
        CAST(NULL AS STRING) AS touchpoint_event_id,
        CAST(NULL AS TIMESTAMP) AS occurred_at,
        CAST(NULL AS STRING) AS touchpoint_type,
        CAST(NULL AS STRING) AS source,
        CAST(NULL AS STRING) AS attribution_deduplication_key
    {% else %}
        -- Touchpoint identification
        {{ create_nexus_id('touchpoint', ['touchpoint_event_id', 'occurred_at']) }} AS touchpoint_id,
        -- Event reference
        touchpoint_event_id,
        -- Timestamp
        occurred_at,
        -- Touchpoint classification
        touchpoint_type,
        -- Source system
        source,
        attribution_deduplication_key
    {% endif %}
{% endmacro %}
