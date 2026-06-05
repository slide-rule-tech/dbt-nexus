{#
  snapshot_diff_events
  --------------------
  Turn a synced, in-place-changing source field into nexus EVENTS by diffing
  its append-only ELT history.

  ELT loaders keep every ingested version of a source row (one per
  `observed_at`, typically `_ingested_at`). A field that is *overwritten in
  place* in the operational system (a "current value only" field) therefore
  leaves a recoverable trail in the raw landing table: each distinct value the
  field ever held is preserved across snapshots. This macro reconstructs that
  trail as one event per distinct (entity, value) — recovering point-in-time
  history retroactively, and backfilling everything observed since ELT began.

  It emits the standard nexus intermediate-event column shape:

      event_id, occurred_at, event_type, event_name, event_description,
      source, value, value_unit, _ingested_at, _processed_at

  plus any caller-supplied domain columns.

  Parameters
  ----------
  source_relation (required)
      The append-only relation holding ALL snapshot versions — typically a
      `source(...)` (NOT a deduped `ref(...)`). Pass the Jinja relation, e.g.
      `source('salesforce', 'salesforce_accounts')`.

  entity_key (required)
      SQL expression for the entity identifier (e.g. `"id"`, or
      `"json_extract_scalar(_raw_record, '$.Id')"`).

  value_expr (required)
      SQL expression for the tracked field, evaluated against `source_relation`.
      NULL / empty values are dropped (they are not "what happened").

  event_name (required)
      The nexus `event_name` string (also used as `event_type` unless
      `event_type` is given).

  event_type (default = event_name)
      The nexus `event_type` string.

  source (default 'unknown')
      The nexus `source` string.

  observed_at_column (default '_ingested_at')
      The append-only snapshot timestamp column on `source_relation`. Used to
      pick the FIRST snapshot a (entity, value) pair appeared in, and — in
      `observed` mode — as the event's `occurred_at`.

  occurred_at_mode (default 'value')
      How `occurred_at` is derived:
        - 'value'    : the tracked value IS a business date/timestamp. EXACT.
                       `occurred_at = timestamp(value_expr)`. Preferred when the
                       field is itself a date (e.g. "last reviewed on").
        - 'observed' : the value is not a date; use the first-observed
                       `observed_at_column` instead. HONEST but lag-bounded —
                       `occurred_at` is when we first SAW the value, not when it
                       changed (true change is somewhere in (prev snapshot,
                       this snapshot]).

  grain (default 'distinct_value')
      Which rows become events:
        - 'distinct_value' : one event per distinct (entity, value) the field
                             ever held. Re-using an earlier value does NOT make
                             a new event (idempotent on value). Matches the AWM
                             IPS implementation.
        - 'change'         : one event per value CHANGE in the per-entity
                             snapshot timeline. Distinct from 'distinct_value'
                             only when a value repeats after changing away and
                             back (A -> B -> A yields two A events). Requires
                             `occurred_at_mode = 'observed'` (a repeated value
                             has no distinct business date to anchor on).

  event_description (default = "concat(event_name, ': ', entity_key)")
      SQL expression for the human-readable description.

  value_column / value_unit_column (default NULL)
      SQL expressions for the numeric `value` / `value_unit` nexus columns.
      Default to NULL (most snapshot-diff events are categorical, not measured).

  additional_columns (default {})
      Mapping of {output_alias: sql_expression} for extra domain columns to
      carry onto each event (e.g. {'account_id': 'id', 'account_name': 'name'}).
      Expressions are aggregated with `max()` over the snapshot group so they
      reflect the entity's value as of the first snapshot the (entity, value)
      pair was seen.

  Idempotency
  -----------
  `event_id` is `create_nexus_id('event', [entity_key, value-as-string,
  event_name])`, so re-runs are stable and each distinct value produces its own
  durable event. In 'change' grain the snapshot index is added to the hash so
  repeated values still get distinct, stable ids.

  Edge cases handled
  ------------------
  - First snapshot already has a value: it still becomes an event (its
    `occurred_at` is the value's business date in 'value' mode, or the first
    observation in 'observed' mode — we cannot see further back than ELT does).
  - Multiple changes over time: each distinct value (or each change) is its own
    event.
  - NULL / blank values: excluded.
#}

{% macro snapshot_diff_events(
    source_relation,
    entity_key,
    value_expr,
    event_name,
    event_type=none,
    source='unknown',
    observed_at_column='_ingested_at',
    occurred_at_mode='value',
    grain='distinct_value',
    event_description=none,
    value_column=none,
    value_unit_column=none,
    additional_columns={}
) %}

{%- set event_type = event_type if event_type is not none else event_name -%}
{#- default description references the `entity_key` ALIAS (available in the
    downstream events CTE), not the raw entity_key expression (which may
    reference source columns like _raw_record that don't exist there). -#}
{%- set event_description = event_description
        if event_description is not none
        else "concat('" ~ event_name ~ ": ', cast(entity_key as string))" -%}
{%- set value_column = value_column if value_column is not none else 'cast(null as numeric)' -%}
{%- set value_unit_column = value_unit_column if value_unit_column is not none else 'cast(null as string)' -%}

{%- if grain == 'change' and occurred_at_mode != 'observed' -%}
  {{ exceptions.raise_compiler_error(
      "snapshot_diff_events: grain='change' requires occurred_at_mode='observed' "
      ~ "(a repeated value has no distinct business date to anchor occurred_at).") }}
{%- endif -%}

with all_snapshots as (
    select
        {{ entity_key }} as entity_key,
        {{ value_expr }} as observed_value,
        {{ observed_at_column }} as observed_at
        {%- for alias, expr in additional_columns.items() %},
        {{ expr }} as {{ alias }}
        {%- endfor %}
    from {{ source_relation }}
),

filtered as (
    select *
    from all_snapshots
    where entity_key is not null
      and observed_value is not null
      and trim(cast(observed_value as string)) != ''
),

{% if grain == 'change' %}
-- one event per value CHANGE in the per-entity snapshot timeline
sequenced as (
    select
        *,
        lag(observed_value) over (
            partition by entity_key order by observed_at
        ) as prev_value
    from filtered
),

change_points as (
    select
        *,
        sum(case when prev_value is null or prev_value != observed_value then 1 else 0 end)
            over (partition by entity_key order by observed_at) as change_index
    from sequenced
),

grouped as (
    select
        entity_key,
        observed_value,
        change_index,
        min(observed_at) as first_observed_at
        {%- for alias, expr in additional_columns.items() %},
        max({{ alias }}) as {{ alias }}
        {%- endfor %}
    from change_points
    -- keep only rows that begin a new value run
    where prev_value is null or prev_value != observed_value
    group by entity_key, observed_value, change_index
),
{% else %}
-- one event per DISTINCT (entity, value)
grouped as (
    select
        entity_key,
        observed_value,
        cast(null as integer) as change_index,
        min(observed_at) as first_observed_at
        {%- for alias, expr in additional_columns.items() %},
        max({{ alias }}) as {{ alias }}
        {%- endfor %}
    from filtered
    group by entity_key, observed_value
),
{% endif %}

events as (
    select
        {% if grain == 'change' -%}
        {{ nexus.create_nexus_id('event', ['entity_key', 'cast(observed_value as string)', 'cast(change_index as string)', "'" ~ event_name ~ "'"]) }} as event_id,
        {%- else -%}
        {{ nexus.create_nexus_id('event', ['entity_key', 'cast(observed_value as string)', "'" ~ event_name ~ "'"]) }} as event_id,
        {%- endif %}
        {% if occurred_at_mode == 'value' -%}
        cast(observed_value as timestamp) as occurred_at,
        {%- else -%}
        first_observed_at as occurred_at,
        {%- endif %}
        '{{ event_type }}' as event_type,
        '{{ event_name }}' as event_name,
        {{ event_description }} as event_description,
        '{{ source }}' as source,
        {{ value_column }} as value,
        {{ value_unit_column }} as value_unit,
        first_observed_at as _ingested_at,
        current_timestamp() as _processed_at
        {%- for alias in additional_columns.keys() %},
        {{ alias }}
        {%- endfor %}
    from grouped
)

select * from events
order by occurred_at desc

{% endmacro %}
