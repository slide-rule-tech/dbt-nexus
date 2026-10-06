{# Quote an identifier that came from DATA rather than from source code.

    The core pivots (`nexus_event_dimensions`, `nexus_event_measurements`,
    `nexus_entity_states`) discover their column list at compile time by
    querying distinct dimension / measurement / state names. Those names are
    not controlled by this package — for Segment URL-parameter dimensions they
    are not controlled by anyone, since the param key of any link a visitor
    follows becomes a dimension name.

    Emitting such a name as a bare alias (`... as start`) breaks the whole
    model the first time one of them is a reserved word:

        001003 (42000): SQL compilation error:
        syntax error line 999 at position 72 unexpected 'start'.

    One such row takes down the pivot and everything downstream of it — on
    go-koala a single `?start=` link cascaded into 77 skipped models,
    including nexus_entities, nexus_states and nexus_relationships.

    IDENTITY GUARANTEE. This macro quotes *every* name, not just the reserved
    ones, so there is no keyword list to keep current. It is still a no-op for
    existing columns, because it applies the adapter's own identifier folding
    before quoting — the stored column name is byte-identical to what the bare
    alias produced:

        Snowflake  `as foo`  -> FOO   ==  `as "FOO"`  -> FOO
        BigQuery   `as foo`  -> foo   ==  `as ` foo ` ` -> foo
        Redshift   `as Foo`  -> foo   ==  `as "foo"`  -> foo

    Folding is applied only for adapters that fold. BigQuery and DuckDB
    preserve the case of unquoted identifiers, so their names pass through
    untouched; folding them would rename existing columns.
#}
{% macro quote_dynamic_column(name) -%}
  {{ adapter.quote(nexus.fold_identifier(name)) }}
{%- endmacro %}


{# Apply the adapter's unquoted-identifier case folding to `name`. #}
{% macro fold_identifier(name) -%}
{%- if target.type == 'snowflake' -%}
  {{ name | upper }}
{%- elif target.type in ('redshift', 'postgres') -%}
  {{ name | lower }}
{%- else -%}
  {#- bigquery, duckdb: unquoted identifiers keep their case as written -#}
  {{ name }}
{%- endif -%}
{%- endmacro %}
