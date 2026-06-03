{% macro nexus_bq_informational_constraints(primary_key=none, foreign_keys=[], external_foreign_keys=[]) %}
  {# Returns a list of `ALTER TABLE ... NOT ENFORCED` statements suitable
     for a model's `post_hook=` config. Used to declare BigQuery
     informational primary-key and foreign-key constraints so the query
     optimizer can do join elimination and tighter cardinality estimates.

     BigQuery PK/FK constraints are NOT ENFORCED — they're hints, not
     validations. They're free to add, but if a declared constraint
     doesn't actually hold the optimizer will return WRONG results.
     In nexus they hold by construction: PK uniqueness is dbt-tested
     with severity=error (build halts on violation), and FK referential
     integrity is guaranteed by the build graph topology (every
     dim/measurement/participant row is derived from a nexus_events
     row).

     Usage in a model config:
       {{ config(
           materialized='table',
           post_hook=nexus.nexus_bq_informational_constraints(
               primary_key='event_id',
               foreign_keys=[
                 {'column': 'event_id',
                  'ref_table': 'nexus_events',
                  'ref_column': 'event_id'},
               ],
           ),
       ) }}

     Each emitted ALTER TABLE statement contains literal `{{ this }}`
     Jinja placeholders that dbt re-renders at hook execution time
     (after the model rebuild). FK targets are constructed lexically
     from `{{ this.database }}.{{ this.schema }}.<ref_table>` rather
     than via `ref()` so they don't appear in dbt's compile DAG — the
     core nexus_* models have real dependency cycles via identity
     resolution that `ref()` in a post-hook would expose. All core
     models live in the same dataset by package convention
     (`nexus_{{ target.name }}`), so the sibling lookup is correct.

     Gated on the same `nexus.warehouse_optimization.enabled` toggle
     as the partition/cluster macros, and on `target.type == 'bigquery'`.
     Returns an empty list on Snowflake (post_hook=[] is a clean no-op).
  #}
  {%- if not (nexus.nexus_warehouse_optimization_enabled() and target.type == 'bigquery') -%}
    {%- do return([]) -%}
  {%- endif -%}

  {%- set statements = [] -%}

  {%- if primary_key -%}
    {%- do statements.append(
      'ALTER TABLE {{ this }} ADD PRIMARY KEY (' ~ primary_key ~ ') NOT ENFORCED'
    ) -%}
  {%- endif -%}

  {%- for fk in foreign_keys -%}
    {%- set fk_name = 'fk_' ~ fk.column -%}
    {%- do statements.append(
      'ALTER TABLE {{ this }} ADD CONSTRAINT IF NOT EXISTS ' ~ fk_name ~
      ' FOREIGN KEY (' ~ fk.column ~
      ') REFERENCES `{{ this.database }}.{{ this.schema }}.' ~ fk.ref_table ~
      '` (' ~ fk.ref_column ~ ') NOT ENFORCED'
    ) -%}
  {%- endfor -%}

  {# External FKs are attached to a *sibling* table — for the
     participants → entities case where adding the FK from the
     participants model's post-hook would race with (or cycle with)
     entities' build. Instead, the model that this hook is attached
     to (= the FK-referenced model, e.g. nexus_entities) emits an
     ALTER TABLE on the sibling. By the time this hook runs, the
     sibling table already exists (it's the parent in the DAG). #}
  {%- for fk in external_foreign_keys -%}
    {%- set fk_name = 'fk_' ~ fk.column -%}
    {%- do statements.append(
      'ALTER TABLE `{{ this.database }}.{{ this.schema }}.' ~ fk.on_table ~
      '` ADD CONSTRAINT IF NOT EXISTS ' ~ fk_name ~
      ' FOREIGN KEY (' ~ fk.column ~ ') REFERENCES {{ this }} (' ~
      fk.ref_column ~ ') NOT ENFORCED'
    ) -%}
  {%- endfor -%}

  {%- do return(statements) -%}
{% endmacro %}
