{{ config(materialized='table') }}

{# Query nexus_events to get distinct source_table values at compile time #}
{# We'll use run_query in a macro context, but for now, scan graph for event models #}
{% set source_table_column_map = {} %}

{# Scan graph for all event models that could be source_table values #}
{% for node_id, node in graph.nodes.items() %}
    {% if node.resource_type == 'model' and '_events' in node.name %}
        {% set is_enabled = true %}
        {% if node.config %}
            {% set is_enabled = node.config.get('enabled', true) %}
        {% endif %}
        
        {% if is_enabled %}
            {# Build relation identifier from node information #}
            {# Use adapter.get_relation() with schema and identifier #}
            {% set relation_identifier = api.Relation.create(
                database=target.database,
                schema=node.schema,
                identifier=node.name
            ) %}
            
            {# Get relation using adapter #}
            {% set model_relation = adapter.get_relation(
                database=target.database,
                schema=node.schema,
                identifier=node.name
            ) %}
            
            {# Only proceed if relation exists #}
            {% if model_relation %}
                {% set cols = adapter.get_columns_in_relation(model_relation) %}
                {% set common_fields = var('common_event_fields', []) %}
                {% set common_fields_lower = [] %}
                {% for field in common_fields %}
                    {% do common_fields_lower.append(field.lower()) %}
                {% endfor %}
                {% set column_info = [] %}
                {% for col in cols %}
                    {# Exclude common event fields - only include custom/source-specific columns #}
                    {% set col_name_lower = col.column.lower() %}
                    {% if col_name_lower not in common_fields_lower %}
                        {% do column_info.append({
                            'name': col.column,
                            'type': col.dtype
                        }) %}
                    {% endif %}
                {% endfor %}
                {% do source_table_column_map.update({node.name: column_info}) %}
            {% endif %}
        {% endif %}
    {% endif %}
{% endfor %}

{# Get distinct event metadata from nexus_events #}
WITH distinct_events AS (
    SELECT DISTINCT
        event_name,
        event_type,
        source,
        value_unit,
        source_table
    FROM {{ ref('nexus_events') }}
    WHERE event_name IS NOT NULL
)

SELECT
    de.event_name,
    de.event_type,
    de.source,
    de.value_unit,
    de.source_table,
    {% if source_table_column_map %}
        CASE
            {% for source_table, columns in source_table_column_map.items() %}
            WHEN de.source_table = '{{ source_table }}' THEN TO_JSON_STRING([
                {% for col in columns %}
                STRUCT(
                    '{{ col.name }}' as column_name,
                    '{{ col.type }}' as column_type
                ){% if not loop.last %},{% endif %}
                {% endfor %}
            ])
            {% endfor %}
            ELSE NULL
        END as columns_json
    {% else %}
        NULL as columns_json
    {% endif %}
FROM distinct_events de
ORDER BY de.source, de.event_type, de.event_name, de.value_unit
