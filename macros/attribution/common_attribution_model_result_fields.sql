{% macro common_attribution_model_result_fields(return_empty=false) %}
    {% if return_empty %}
        CAST(NULL AS STRING) AS attribution_model_result_id,
        CAST(NULL AS TIMESTAMP) AS touchpoint_occurred_at,
        CAST(NULL AS STRING) AS attribution_model_name,
        CAST(NULL AS STRING) AS touchpoint_batch_id,
        CAST(NULL AS STRING) AS touchpoint_event_id,
        CAST(NULL AS STRING) AS attributed_event_id,
        CAST(NULL AS STRING) AS person_id,
        CAST(NULL AS TIMESTAMP) AS attributed_event_occurred_at,
        CAST(NULL AS STRING) AS source
    {% else %}
        -- Attribution result identification
        attribution_model_result_id,
        -- Touchpoint timing
        touchpoint_occurred_at,
        -- Model identification
        attribution_model_name,
        -- Touchpoint references
        touchpoint_batch_id,
        touchpoint_event_id,
        -- Attribution target
        attributed_event_id,
        -- Person context
        person_id,
        -- Event timing
        attributed_event_occurred_at,
        -- Source system
        source
    {% endif %}
{% endmacro %}
