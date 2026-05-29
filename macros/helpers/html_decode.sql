{% macro html_decode(text) %}
-- Decode common HTML entities in text
-- Handles: &#39; (apostrophe), &apos;, &quot;, &amp;, &lt;, &gt;, &#160; (non-breaking space)
REGEXP_REPLACE(
    REGEXP_REPLACE(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE({{ text }}, ''),
                            {% if target.type == 'bigquery' %}r'&#39;'{% else %}'&#39;'{% endif %}, {% if target.type == 'bigquery' %}"'"{% else %}''''{% endif %}  -- Apostrophe
                        ),
                        {% if target.type == 'bigquery' %}r'&apos;'{% else %}'&apos;'{% endif %}, {% if target.type == 'bigquery' %}"'"{% else %}''''{% endif %}  -- Apostrophe (named)
                    ),
                    {% if target.type == 'bigquery' %}r'&quot;'{% else %}'&quot;'{% endif %}, '"'  -- Double quote
                ),
                {% if target.type == 'bigquery' %}r'&amp;'{% else %}'&amp;'{% endif %}, '&'  -- Ampersand
            ),
            {% if target.type == 'bigquery' %}r'&lt;'{% else %}'&lt;'{% endif %}, '<'  -- Less than
        ),
        {% if target.type == 'bigquery' %}r'&gt;'{% else %}'&gt;'{% endif %}, '>'  -- Greater than
    ),
    {% if target.type == 'bigquery' %}r'&#160;'{% else %}'&#160;'{% endif %}, ' '  -- Non-breaking space
)
{% endmacro %}

