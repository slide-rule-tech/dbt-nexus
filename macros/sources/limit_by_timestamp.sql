{% macro limit_by_timestamp(
    timestamp_column='occurred_at',
    dev_limit=none,
    prod_limit=none
) %}
{#
    Filters data by timestamp based on target environment and configured limits.
    
    Parameters:
        timestamp_column (str): Column name to filter on. Default: 'occurred_at'
        dev_limit (str): Override for dev environment timestamp. Format: 'YYYY-MM-DD'. Optional.
        prod_limit (str): Override for prod environment timestamp. Format: 'YYYY-MM-DD'. Optional.
    
    Behavior:
        - In dev target: Uses dev_timestamp_limit var or dev_limit parameter
        - In prod target: Uses prod_timestamp_limit var or prod_limit parameter
        - If no limit is configured, returns 'true' (no filtering)
    
    Returns:
        SQL condition for WHERE clause (e.g., "occurred_at >= '2022-01-01'")
    
    Usage:
        -- In intermediate event models:
        select * from base_events
        where event_date is not null
          and {{ nexus.limit_by_timestamp() }}
        
        -- With custom column:
        where {{ nexus.limit_by_timestamp('enrollment_date') }}
        
        -- With override:
        where {{ nexus.limit_by_timestamp(dev_limit='2023-01-01') }}
        
    Configuration in dbt_project.yml:
        vars:
          dev_timestamp_limit: '2022-01-01'
          prod_timestamp_limit: '2020-01-01'  # Optional
#}

    {%- set limit_timestamp = none -%}
    {%- set target_name = (target.name | lower) if target.name is not none else '' -%}

    {#- Determine which limit to use based on target -#}
    {%- if target_name.startswith('dev') -%}
        {#- Dev environment: check parameter first, then variable -#}
        {%- if dev_limit is not none -%}
            {%- set limit_timestamp = dev_limit -%}
        {%- elif var('dev_timestamp_limit', none) is not none -%}
            {%- set limit_timestamp = var('dev_timestamp_limit') -%}
        {%- endif -%}
        
    {%- elif target_name.startswith('prod') or target_name == 'default' -%}
        {#- Prod environment: check parameter first, then variable -#}
        {%- if prod_limit is not none -%}
            {%- set limit_timestamp = prod_limit -%}
        {%- elif var('prod_timestamp_limit', none) is not none -%}
            {%- set limit_timestamp = var('prod_timestamp_limit') -%}
        {%- endif -%}
    {%- endif -%}
    
    {#- Generate filter condition or return true if no limit -#}
    {%- if limit_timestamp is not none -%}
        {{ timestamp_column }} >= '{{ limit_timestamp }}'
    {%- else -%}
        true
    {%- endif -%}

{% endmacro %}

