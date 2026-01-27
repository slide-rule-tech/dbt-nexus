{% macro customer_io_identify(
    entity_type='person',
    user_id_column='user_id',
    anonymous_id_column=none,
    dedupe_column='email',
    ignore_traits=[],
    rename_traits={},
    filters=[]
) %}
{#
    Customer.io Identify Sync Macro
    
    Generates a Customer.io-compatible identify sync output from nexus_entities.
    
    Parameters:
    - entity_type: Entity type to select ('person', 'group')
    - user_id_column: Column to use as Customer.io userId
    - anonymous_id_column: Column to use as anonymousId (optional)
    - dedupe_column: Column to deduplicate by (lowercased/trimmed)
    - ignore_traits: List of trait column names to exclude from output
    - rename_traits: Dict mapping original_name -> new_name for renaming columns
    - filters: List of additional WHERE clause conditions
    
    Reference: https://docs.customer.io/integrations/data-in/connections/reverse-etl/snowflake/#identify
#}

{# Get all columns from nexus_entities at compile time #}
{% set entities_relation = ref('nexus_entities') %}
{% set all_columns = adapter.get_columns_in_relation(entities_relation) %}

{# System columns that are handled specially or excluded #}
{% set system_columns = [
    'entity_id',
    'entity_type',
    '_processed_at',
    'traits_entity_id'
] %}

{# Timestamp columns that need TO_TIMESTAMP_NTZ transformation #}
{% set timestamp_types = ['TIMESTAMP_NTZ', 'TIMESTAMP_LTZ', 'TIMESTAMP_TZ', 'DATE', 'DATETIME', 'TIMESTAMP'] %}

{# Columns that are used for Customer.io special fields (not traits) #}
{% set special_columns = [user_id_column] %}
{% if anonymous_id_column %}
    {% do special_columns.append(anonymous_id_column) %}
{% endif %}

{# Default renames for Customer.io reserved traits (user can override via rename_traits) #}
{% set default_renames = {
    '_created_at': 'created_at'
} %}
{% set merged_renames = default_renames %}
{% for key, value in rename_traits.items() %}
    {% do merged_renames.update({key: value}) %}
{% endfor %}

{# Build the list of trait columns to output #}
{% set trait_columns = [] %}
{% for col in all_columns %}
    {% set col_name = col.column | lower %}
    {# Skip system columns, special columns, and ignored traits #}
    {% if col_name not in system_columns 
       and col_name not in special_columns 
       and col_name not in ignore_traits %}
        {% do trait_columns.append({'name': col_name, 'dtype': col.dtype | upper}) %}
    {% endif %}
{% endfor %}

WITH base_entities AS (
    SELECT 
        {# Customer.io required fields #}
        {{ user_id_column }} AS "userId"
        {% if anonymous_id_column %},
        {{ anonymous_id_column }} AS "anonymousId"
        {% endif %},
        _updated_at AS "timestamp",
        
        {# Trait columns - dynamically generated #}
        {% for col in trait_columns %}
            {% set output_name = merged_renames.get(col.name, col.name) %}
            {% if col.dtype in timestamp_types %}
        TO_TIMESTAMP_NTZ({{ col.name }}) AS "{{ output_name }}"{% if not loop.last %},{% endif %}
            {% else %}
        {{ col.name }} AS "{{ output_name }}"{% if not loop.last %},{% endif %}
            {% endif %}
        {% endfor %}

    FROM {{ ref('nexus_entities') }}

    WHERE entity_type = '{{ entity_type }}'
      AND ({{ user_id_column }} IS NOT NULL{% if anonymous_id_column %} OR {{ anonymous_id_column }} IS NOT NULL{% endif %})
      {% for filter_condition in filters %}
      AND {{ filter_condition }}
      {% endfor %}
)

SELECT *
FROM base_entities
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY LOWER(TRIM("{{ merged_renames.get(dedupe_column, dedupe_column) }}")) 
    ORDER BY "timestamp" DESC NULLS LAST
) = 1

{% endmacro %}
