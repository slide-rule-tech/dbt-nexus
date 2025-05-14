{% macro real_time_event_filter(event_id_column='event_id') %}
  WHERE 1=1
    {% if var('realtime_event_id', none) %}
      AND {{ event_id_column }} IN {{ var("realtime_event_id") }}
    {% endif %}
{% endmacro %} 