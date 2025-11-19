{% macro common_event_fields(realtime_processed) %}
    {# Get common event fields from var - keeps definition DRY #}
    {% set common_fields = var('common_event_fields', []) %}
    {% for field in common_fields %}
        {% if field == 'realtime_processed' %}
            {# Special handling for realtime_processed with conditional logic #}
            {% if realtime_processed == 'TRUE' %}TRUE{% else %}FALSE{% endif %} as realtime_processed{% if not loop.last %},{% endif %}
        {% else %}
            {{ field }}{% if not loop.last %},{% endif %}
        {% endif %}
    {% endfor %}
{% endmacro %} 