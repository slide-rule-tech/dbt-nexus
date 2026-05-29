{# Cross-adapter dedup-by-key macro.

    Replaces the pattern:
        select <cols> from <source>
        qualify row_number() over (partition by <pkey> order by <tiebreak>) = 1

    With a single macro call:
        {{ nexus_dedupe('<source>', '<pkey>', '<tiebreak>', cols='*') }}

    Why this exists: DuckDB has a query-planner bug where QUALIFY inside a
    CTAS interacts poorly with try_strptime + many-column SELECTs,
    producing spurious "invalid timestamp field format" errors. The
    subquery + WHERE __rn = 1 form is semantically identical, portable
    across adapters, and dodges the bug.

    On Snowflake and BigQuery we emit the QUALIFY form (both support
    it) for compiled-SQL readability. On DuckDB (and as the safe
    default) we emit the subquery form, using `* EXCLUDE(__nexus_rn)`
    on duck and `* EXCEPT(__nexus_rn)` on BigQuery for `cols='*'`.

    Args:
      source: CTE name or {{ ref('...') }} expression (string)
      partition_by: comma-separated column list (string)
      order_by: comma-separated order clause (string, e.g.
                'etl_load_dt desc nulls last')
      cols: column list for the outer select (defaults to '*')
#}
{% macro dedupe(source, partition_by, order_by, cols='*') %}
{%- if target.type == 'snowflake' or target.type == 'bigquery' -%}
select {{ cols }} from {{ source }}
qualify row_number() over (partition by {{ partition_by }} order by {{ order_by }}) = 1
{%- else -%}
select
  {%- if cols == '*' %} * exclude(__nexus_rn)
  {%- else %} {{ cols }}
  {%- endif %}
from (
    select *,
      row_number() over (partition by {{ partition_by }} order by {{ order_by }}) as __nexus_rn
    from {{ source }}
)
where __nexus_rn = 1
{%- endif -%}
{% endmacro %}
