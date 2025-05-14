{% macro common_event_fields(realtime_processed) %}
    -- Primary Key
    event_id,
    -- Timestamp
    occurred_at,
    -- Event details
    event_name,
    event_description,
    event_value,
    value_unit,
    -- Metadata for lineage
    event_type,
    source,
    source_table,
    -- Timestamps for watermarking and lineage
    synced_at,
    -- Processing metadata
    {% if realtime_processed == 'TRUE' %}TRUE{% else %}FALSE{% endif %} as realtime_processed
{% endmacro %} 