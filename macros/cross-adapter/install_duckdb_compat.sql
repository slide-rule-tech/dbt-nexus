{# Snowflake-compat shims for DuckDB targets.

    Returns a single SQL string (multi-statement is fine — DuckDB
    accepts it) that:

      1. Aliases Snowflake-specific type names (TIMESTAMP_NTZ, etc.)
         to native DuckDB types so cast(... as timestamp_ntz) works.
      2. Defines DuckDB MACROs that mimic Snowflake scalar functions
         lacking native DuckDB equivalents (iff, regexp_substr,
         regexp_like, try_parse_json, try_to_double, try_to_number,
         array_construct, array_contains, current_timestamp()).
      3. Disables DuckDB's expression_rewriter optimizer, which has a
         bug where try_strptime + windowed dedup + many-column CTAS
         produces spurious "invalid timestamp format" errors.

    Consumers call this from `on-run-start` in their dbt_project.yml:

        on-run-start:
          - "{{ nexus.install_duckdb_compat() }}"

    No-op on non-DuckDB targets — returns an empty string.
#}
{% macro install_duckdb_compat() %}
{%- if target.type != 'duckdb' -%}
{%- else -%}
-- Snowflake type aliases
CREATE TYPE IF NOT EXISTS timestamp_ntz AS TIMESTAMP;
CREATE TYPE IF NOT EXISTS timestamp_tz AS TIMESTAMPTZ;
CREATE TYPE IF NOT EXISTS variant AS JSON;

-- Snowflake scalar function aliases
CREATE OR REPLACE MACRO current_timestamp() AS now();
CREATE OR REPLACE MACRO iff(c, t, f) AS CASE WHEN c THEN t ELSE f END;
CREATE OR REPLACE MACRO regexp_substr(s, p, pos := 1, occ := 1, mode := 'c', grp := 0) AS
    CASE WHEN mode = 'e' THEN regexp_extract(s, p, grp)
         ELSE regexp_extract(s, p) END;
CREATE OR REPLACE MACRO regexp_like(s, p) AS regexp_matches(s, p);
CREATE OR REPLACE MACRO try_parse_json(s) AS try_cast(s AS json);
CREATE OR REPLACE MACRO try_to_double(s) AS try_cast(s AS double);
CREATE OR REPLACE MACRO try_to_number(s) AS try_cast(s AS decimal(38,0));
CREATE OR REPLACE MACRO array_construct() AS list_value();
CREATE OR REPLACE MACRO array_contains(needle, haystack) AS list_contains(haystack, needle);

-- Disable expression_rewriter: bug where try_strptime + windowed dedup
-- in a many-column CTAS surfaces as "invalid timestamp field format"
-- against a column unrelated to the cast. Small (likely negligible)
-- perf cost in dev.
SET disabled_optimizers='expression_rewriter';
{%- endif -%}
{% endmacro %}
