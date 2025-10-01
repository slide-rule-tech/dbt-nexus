{% macro validate_and_normalize_phone(phone_expr) -%}
    {#-
      Basic phone validation + normalization across warehouses.
      
      Behavior:
        - trim whitespace
        - return NULL if contains '@' (likely an email)
        - return NULL if empty or null
        - return trimmed value if it looks like a phone number
      
      Usage:
        select {{ validate_and_normalize_phone('users.phone') }} as phone_norm from {{ ref('stg_users') }}
      
      Notes:
        - This is a basic implementation that filters out obvious non-phone values
        - Can be extended with more sophisticated phone validation as needed
    -#}

    {%- if target.type == 'bigquery' -%}
        (
          case
            when {{ phone_expr }} is null then null
            when trim({{ phone_expr }}) = '' then null
            when contains_substr(trim({{ phone_expr }}), '@') then null
            else trim({{ phone_expr }})
          end
        )

    {%- elif target.type == 'snowflake' -%}
        (
          case
            when {{ phone_expr }} is null then null
            when trim({{ phone_expr }}) = '' then null
            when contains(trim({{ phone_expr }}), '@') then null
            else trim({{ phone_expr }})
          end
        )

    {%- elif target.type in ['postgres', 'redshift'] -%}
        (
          case
            when {{ phone_expr }} is null then null
            when trim({{ phone_expr }}) = '' then null
            when position('@' in trim({{ phone_expr }})) > 0 then null
            else trim({{ phone_expr }})
          end
        )

    {%- elif target.type in ['databricks', 'spark'] -%}
        (
          case
            when {{ phone_expr }} is null then null
            when trim({{ phone_expr }}) = '' then null
            when instr(trim({{ phone_expr }}), '@') > 0 then null
            else trim({{ phone_expr }})
          end
        )

    {%- else -%}
        {# Generic fallback using contains/position where available #}
        (
          case
            when {{ phone_expr }} is null then null
            when trim({{ phone_expr }}) = '' then null
            when contains(trim({{ phone_expr }}), '@') then null
            else trim({{ phone_expr }})
          end
        )
    {%- endif -%}
{%- endmacro %}
