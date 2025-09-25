{% macro validate_and_normalize_email(email_expr) -%}
    {#-
      Normalize + validate an email across warehouses.

      Behavior:
        - lower(trim(email))
        - validate against a conservative regex (ASCII; local: [A-Za-z0-9._%+-])
        - if domain in ('gmail.com','googlemail.com'), remove '.' from the local part
        - return NULL if invalid or empty

      Usage:
        select {{ normalize_email('users.email') }} as email_norm from {{ ref('stg_users') }}

      Notes:
        - Regex is intentionally conservative (common production heuristic).
        - Extend as needed for IDN/Unicode if your warehouse & data require it.
    -#}
    {%- set pattern = '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' -%}

    {%- if target.type == 'bigquery' -%}
        (
          case
            when {{ email_expr }} is null then null
            when not REGEXP_CONTAINS(lower(trim({{ email_expr }})), r'{{ pattern }}') then null
            else
              -- split into local/dom; strip dots in local for gmail/googlemail
              case
                when lower(split(lower(trim({{ email_expr }})), '@')[safe_offset(1)]) in ('gmail.com','googlemail.com') then
                  concat(
                    replace(split(lower(trim({{ email_expr }})), '@')[offset(0)], '.', ''),
                    '@',
                    split(lower(trim({{ email_expr }})), '@')[safe_offset(1)]
                  )
                else
                  lower(trim({{ email_expr }}))
              end
          end
        )

    {%- elif target.type == 'snowflake' -%}
        (
          case
            when {{ email_expr }} is null then null
            when not regexp_like(lower(trim({{ email_expr }})), '{{ pattern }}') then null
            else
              case
                when lower(split_part(lower(trim({{ email_expr }})), '@', 2)) in ('gmail.com','googlemail.com') then
                  replace(split_part(lower(trim({{ email_expr }})), '@', 1), '.', '')
                  || '@' ||
                  split_part(lower(trim({{ email_expr }})), '@', 2)
                else
                  lower(trim({{ email_expr }}))
              end
          end
        )

    {%- elif target.type in ['postgres', 'redshift'] -%}
        (
          case
            when {{ email_expr }} is null then null
            when not (lower(trim({{ email_expr }})) ~* '{{ pattern }}') then null
            else
              case
                when lower(split_part(lower(trim({{ email_expr }})), '@', 2)) in ('gmail.com','googlemail.com') then
                  replace(split_part(lower(trim({{ email_expr }})), '@', 1), '.', '')
                  || '@' ||
                  split_part(lower(trim({{ email_expr }})), '@', 2)
                else
                  lower(trim({{ email_expr }}))
              end
          end
        )

    {%- elif target.type in ['databricks', 'spark'] -%}
        (
          case
            when {{ email_expr }} is null then null
            when not (lower(trim({{ email_expr }})) rlike '{{ pattern }}') then null
            else
              case
                when lower(split(lower(trim({{ email_expr }})), '@')[1]) in ('gmail.com','googlemail.com') then
                  concat(
                    replace(split(lower(trim({{ email_expr }})), '@')[0], '.', ''),
                    '@',
                    split(lower(trim({{ email_expr }})), '@')[1]
                  )
                else
                  lower(trim({{ email_expr }}))
              end
          end
        )

    {%- else -%}
        {# Generic fallback using split_part / regex_like where available.
           If your adapter hits this branch and fails, add a specific branch. #}
        (
          case
            when {{ email_expr }} is null then null
            when not regexp_like(lower(trim({{ email_expr }})), '{{ pattern }}') then null
            else
              case
                when lower(split_part(lower(trim({{ email_expr }})), '@', 2)) in ('gmail.com','googlemail.com') then
                  replace(split_part(lower(trim({{ email_expr }})), '@', 1), '.', '')
                  || '@' ||
                  split_part(lower(trim({{ email_expr }})), '@', 2)
                else
                  lower(trim({{ email_expr }}))
              end
          end
        )
    {%- endif -%}
{%- endmacro %}