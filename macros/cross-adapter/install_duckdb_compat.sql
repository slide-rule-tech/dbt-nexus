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

-- BigQuery type aliases (int64, bool already valid in duck; float64,
-- number, string are the BQ-specific names duck doesn't recognize).
CREATE TYPE IF NOT EXISTS float64 AS DOUBLE;
CREATE TYPE IF NOT EXISTS number AS DECIMAL(38,9);
CREATE TYPE IF NOT EXISTS string AS VARCHAR;

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

-- BigQuery scalar function aliases (used by clients ported from BQ).
-- These let BigQuery-shaped SQL like
--     JSON_EXTRACT_SCALAR(_raw_record, '$.id')
--     UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.lines'))
--     TO_JSON_STRING(_raw_record)
-- compile + run on duck without per-call refactoring. The cross-
-- adapter nexus.json_path / nexus.try_to_date macros are still the
-- preferred form for *new* code (they cover BQ/Snowflake/duck under
-- one signature), but shims here unblock large existing BQ codebases.
CREATE OR REPLACE MACRO json_extract_scalar(col, path) AS json_extract_string(col, path);
-- json_extract returns JSON; unnest wants a LIST. Cast to JSON[] so
-- UNNEST(JSON_EXTRACT_ARRAY(...)) works the same shape as on BQ.
CREATE OR REPLACE MACRO json_extract_array(col, path) AS json_extract(col, path)::JSON[];
-- ARRAY_LENGTH on a JSON array: cast then list length.
CREATE OR REPLACE MACRO array_length(arr) AS len(arr);
CREATE OR REPLACE MACRO to_json_string(col) AS cast(col AS varchar);
-- BigQuery's TIMESTAMP(x) constructor: from a string or DATETIME,
-- returns a TIMESTAMP. DuckDB equivalent: cast as timestamp. Wrapping
-- in try_cast for parse-fail tolerance (BQ raises, so use plain cast
-- if strict semantics are wanted).
CREATE OR REPLACE MACRO timestamp(x) AS cast(x AS timestamp);
CREATE OR REPLACE MACRO parse_timestamp(fmt, s) AS strptime(s, fmt);
CREATE OR REPLACE MACRO parse_date(fmt, s) AS cast(strptime(s, fmt) AS date);
CREATE OR REPLACE MACRO timestamp_seconds(x) AS to_timestamp(x);
CREATE OR REPLACE MACRO timestamp_micros(x) AS make_timestamp(x);
CREATE OR REPLACE MACRO unix_seconds(x) AS cast(epoch(x) AS bigint);
CREATE OR REPLACE MACRO unix_micros(x) AS cast(epoch_us(x) AS bigint);
CREATE OR REPLACE MACRO parse_json(s) AS cast(s AS json);
CREATE OR REPLACE MACRO regexp_contains(s, p) AS regexp_matches(s, p);
-- BigQuery SAFE_CAST / SAFE.CAST returns NULL on cast failure. DuckDB
-- has try_cast as the native equivalent. SAFE_CAST isn't a macro-
-- definable function name in duck (the SAFE namespace is BQ-specific),
-- so the cross-adapter approach for `SAFE.CAST` is to refactor to
-- `try_cast`. We register safe_cast (underscore form) as the alias
-- since duck accepts that as a function name.
CREATE OR REPLACE MACRO safe_cast(col, "type") AS try_cast(col AS varchar);

-- Disable expression_rewriter: bug where try_strptime + windowed dedup
-- in a many-column CTAS surfaces as "invalid timestamp field format"
-- against a column unrelated to the cast. Small (likely negligible)
-- perf cost in dev.
SET disabled_optimizers='expression_rewriter';

-- Match Snowflake's UTC session timezone. Without this, DuckDB's
-- session TZ defaults to the host's local TZ, and the SQL idiom
--   cast(<timestamptz expr> as timestamp)
-- (used by nexus.convert_timezone among other places) extracts the
-- wall-clock value in local TZ rather than UTC. The result is
-- timestamps offset by the local-UTC delta — visible as
-- boundary events shifting between calendar days/months relative
-- to Snowflake builds. Pinning the session to UTC aligns duck
-- with Snowflake's session_parameters.TIMEZONE='UTC'.
SET TimeZone='UTC';
{%- endif -%}
{% endmacro %}
