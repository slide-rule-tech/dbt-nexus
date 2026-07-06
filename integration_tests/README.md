# dbt-nexus integration tests

Multi-run scenario harness for **incremental identity resolution**
(`docs/incremental-identity-resolution.md` §6), run against scratch DuckDB
databases. This project is also the reference "consumer": it installs the
package via `local: ..`, wires a synthetic `it` source into the nexus config,
and runs with `nexus.incremental.enabled: true`.

## Run it

```bash
cd integration_tests
python3 run.py                    # all scenarios
python3 run.py simple_merge       # one scenario
python3 run.py --keep-going       # don't stop at first failure
```

Requirements: `dbt-duckdb` and the `duckdb` python package (both present in
the nexus-python env). `run.py` runs `dbt deps` on first use.

Each scenario leaves its database behind for inspection:

```bash
duckdb integration_tests/target/scenarios/simple_merge.duckdb \
  -c "select * from nexus_resolution_log order by resolved_at_watermark"
```

## How it works: the simulated ingestion clock

Incremental correctness is a property of run **sequences**, not states, so
the harness has two layers:

1. **`run.py`** drives sequences. The entire scenario lives in
   `seeds/it_identifier_rows.csv` with an `_ingested_at` column; the source
   shim (`models/it_source/it_entity_identifiers.sql`) exposes only rows
   `<= var('it_now')`. The runner advances `it_now` across dbt invocations —
   each step is one "batch arriving". Step 1 runs on an empty database, so
   it exercises the resolver's full path (the epoch), exactly like a real
   consumer's first build. The runner then asserts the sequence properties
   dbt tests can't see:
   - **id stability**: an identifier's entity changes only via a logged
     `repointed` entry
   - **log append-only**
   - **idempotency**: re-running the final step changes nothing
   - **empty batch** is a clean no-op (scenarios with `empty_final_step`)
   - **watermark advancement** on change-free batches (`reobserved` fix)

2. **`tests/*.sql`** (tag `it_invariant`) assert state invariants after
   every step, most importantly **partition equality**: the incremental
   mapping must group identifiers exactly like `it_shadow_resolved_*` — the
   trusted full-resolution algorithm rebuilt from scratch over the same
   clock-visible slice each step. Entity ids are deliberately ignored
   (labels are bookkeeping; co-membership is the theorem). Because every
   step is checked against the from-scratch result, batch-slicing
   insensitivity is covered transitively — no separate replay runs needed.

## Scenarios

| scenario | what it proves |
| --- | --- |
| `birth_singleton` | new identifier with no edges mints a new entity (`born`) |
| `accretion` | new identifier joins an existing entity; its id doesn't churn |
| `simple_merge` | new edge fuses two entities; loser's rows repointed, survivor by size/tie-break |
| `chain_within_batch` | 3 entities fused via 2 brand-new bridges in ONE batch — real connected components on the contracted graph, not per-edge lookups |
| `chain_across_batches` | A absorbs B, then absorbs C next batch — the mapping stays fully compressed through chained merges |
| `reobserved_watermark` | a batch of only already-known identifiers still advances the watermark (regression test) |
| `out_of_order` | an event that *occurred* before existing data but *arrived* after resolves identically (ingestion-time watermarks) |
| `groups_merge` | group-type merge + a person identifier in the same event (cross-entity-type edges don't bleed between resolvers) |

## Adding a scenario

1. Add rows to `seeds/it_identifier_rows.csv` under a new `scenario` name.
   Batches are just distinct `_ingested_at` values; the runner discovers the
   steps from the seed.
2. Add an entry to `EXPECT` in `run.py` (final entity counts, log reason
   counts excluding the `full_resolution` epoch, `same_entity` /
   `distinct_entities` groupings).

All invariants (partition equality, hygiene, sequence properties) apply to
every scenario automatically.

## Notes

- The `dispatch` config in `dbt_project.yml` exists because the shadow models
  call the package's adapter-dispatched macros from the root project; see the
  comment there. A consumer that only builds package models doesn't need it.
- Do **not** point real consumers at anything in here — the simulated clock
  (`it_now`/`it_scenario`) is test scaffolding by design.
