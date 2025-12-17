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
                            r'&#39;', "'"  -- Apostrophe
                        ),
                        r'&apos;', "'"  -- Apostrophe (named)
                    ),
                    r'&quot;', '"'  -- Double quote
                ),
                r'&amp;', '&'  -- Ampersand
            ),
            r'&lt;', '<'  -- Less than
        ),
        r'&gt;', '>'  -- Greater than
    ),
    r'&#160;', ' '  -- Non-breaking space
)
{% endmacro %}

