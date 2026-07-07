{#
  Touched-group incrementality for ROLLUP models (GROUP BY collapses many
  child rows into one group row), used by the gmail thread / cross-account
  tables. The append recipe is wrong for rollups: a new child must recompute
  its whole group, and the rollup's own _ingested_at is MIN/MAX of the group
  (frozen for MIN), so it cannot be the cursor either.

  Pattern (see gmail_threads_by_account for the reference conversion):
    1. Every rollup emits `_watermark_ingested_at = MAX(child _ingested_at)`
       per group — the reliable cursor.
    2. On incremental runs, `nexus_incremental_touched_groups()` renders the
       distinct group keys among upstream rows past that cursor.
    3. The model inner-joins full upstream history to the touched keys and
       runs its UNCHANGED aggregation over just those groups.
    4. dbt merges on the OUTPUT-grain unique_key. There is no delete leg:
       children are append-only, so a group's output can gain rows but never
       lose them.

  Consumers of a rollup must use the rollup's _watermark_ingested_at as
  their batch clock (the "rollup-child clock" rule) — its _ingested_at may
  be a frozen MIN.
#}

{% macro nexus_incremental_touched_groups(upstream_relation, group_keys, upstream_column='_ingested_at', watermark_column='_watermark_ingested_at') %}
select distinct {{ group_keys | join(', ') }}
from {{ upstream_relation }}
where {{ upstream_column }} > {{ nexus.nexus_incremental_watermark_literal(watermark_column) }}
{% endmacro %}


{#
  Null-safe equi-join predicate over the group keys. IS NOT DISTINCT FROM is
  the one spelling BigQuery, DuckDB and Snowflake all accept; a plain `=`
  silently drops NULL-keyed groups (e.g. a NULL _stream_id) and tuple-IN
  subqueries are not portable across the three adapters.
#}
{% macro nexus_incremental_touched_join(left_alias, right_alias, group_keys) %}
{%- for k in group_keys %}
    {{ 'on' if loop.first else 'and' }} {{ left_alias }}.{{ k }} is not distinct from {{ right_alias }}.{{ k }}
{%- endfor %}
{% endmacro %}


{#
  Compile-time contract for shared-watermark unions (nexus_events, the
  event measurement/dimension unions): one shared watermark across a union
  means a source model missing _ingested_at loses rows SILENTLY. When the
  incremental flag is on, fail loudly naming the offenders instead. Only
  BUILT relations count (a relation with zero columns hasn't been created
  yet — first runs stay quiet).
#}
{% macro nexus_incremental_require_ingested_at(relations, what) %}
  {%- if execute and nexus.nexus_incremental_enabled() -%}
    {%- set missing = [] -%}
    {%- for rel in relations -%}
      {%- set cols = adapter.get_columns_in_relation(rel) | map(attribute='name') | map('lower') | list -%}
      {%- if cols | length > 0 and '_ingested_at' not in cols -%}
        {%- do missing.append(rel | string) -%}
      {%- endif -%}
    {%- endfor -%}
    {%- if missing | length > 0 -%}
      {{ exceptions.raise_compiler_error(
          "nexus incremental: every model feeding " ~ what ~ " must expose a stable "
          ~ "_ingested_at (real ingestion time — never occurred_at, never now()). "
          ~ "Missing from: " ~ missing | join(", ")
          ~ ". Fix the source model, disable the source, or turn off "
          ~ "nexus.incremental.enabled. See docs/incremental-identity-resolution.md.") }}
    {%- endif -%}
  {%- endif -%}
{% endmacro %}
