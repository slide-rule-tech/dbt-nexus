# Incremental Identity Resolution

**Status:** experimental, flag-gated (`nexus.incremental.enabled`, default
`false`). With the flag off, every model behaves exactly as before.

This document is both the design rationale and the spec. It exists because
incremental entity resolution is not just a materialization change — it
changes what an entity id *is* — and future contributors need the reasoning,
not just the code.

---

## 1. Motivation

Every dbt-nexus run today rebuilds the entire pipeline from scratch: every
event, every identifier, every edge, and a full connected-components traversal
over the whole identity graph. Cost and wall-clock scale with total history,
not with what changed. The blocker to incrementality was identity resolution:
a new event can create a brand-new entity, attach identifiers to an existing
entity, or merge two previously separate entities — and naïve incremental
models can't express "merge."

## 2. Conceptual foundations

### 2.1 Full refresh and incremental are different ontologies

A full-refresh pipeline treats the entity graph as a **pure function of
history**: identity is memoryless, everything can be rederived. An incremental
pipeline treats it as **state that evolves**: entities are born, accrete
identifiers, and merge. Identity acquires a biography.

That difference surfaces as a small impossibility result: an id can be
**content-deterministic** (any two people resolving the same full history get
identical ids — the current hash-of-lexicographically-min-identifier scheme)
or **prefix-stable** (ids never churn as data arrives), but not both. A label
that is stable from birth cannot be a deterministic function of a final set
you haven't seen yet.

Incremental mode picks prefix-stability. Consequences:

- Entity ids become **path-dependent**: they depend on ingestion order.
  Replaying the same data in different batch boundaries yields the same
  *grouping* with possibly different id biographies. Dev and prod can differ.
- A future full refresh reassigns ids (it re-derives content-addressed
  labels). Full refreshes become rare, announced events, not a scheduled
  crutch.

This is acceptable because of the position taken in §2.3.

### 2.2 The partition is monotone; only the labels are hard

If edges only ever *arrive* (never get retracted), connected components are
**monotone**: components merge, never split. Merging is associative,
commutative, idempotent — the partition (which identifiers belong together)
is order-insensitive. All order-sensitivity lives in the *labeling* (which
entity_id names each group).

Monotonicity yields the central computational trick — **prior state is a
graph contraction**:

> The identifier → entity_id mapping from the last run is a *lossless
> summary of all prior connectivity*. Each resolved component enters the next
> run's graph as a single contracted super-node. Connected components then
> run over (touched super-nodes + new identifiers + new edges) only — a graph
> proportional to **batch size**, not history size. Old edges are never
> re-read.

In union-find terms: the persisted mapping is a union-find structure fully
path-compressed after every batch; every identifier points directly at its
root, so "find" is a single join.

An alternative "look-ahead" design (pull the full edge sets of touched
components into a dirty-subgraph and re-run CC over raw edges) is also
correct, but suffers adverse selection: the probability a component is
touched by a batch scales with its activity, which correlates with its size —
so the largest components get fully re-resolved almost every run. Contraction
represents a touched 100k-identifier component as one node. Expansion is kept
conceptually in reserve as the *split surgery* tool (§2.5), not the daily
path.

### 2.3 Entity ids are surrogate keys; identifiers are the API

Every entry point into the system is "look up the entity by an identifier"
(Kevin by his email). So identifiers are the stable external names; entity_id
is internal bookkeeping whose only jobs are (a) consistency at any point in
time, and (b) changing rarely enough that changes are **enumerable**.
Identifier-based lookup is self-healing across merges: the path to the entity
survives even when the id doesn't.

The enumerable-changes property is load-bearing: the incremental algorithm
hands downstream a tight contract — *the set of entity_ids that changed this
run = newly born entities + the merge log*. If ids could churn on pure
accretion (as the content-addressed scheme does when a new identifier sorts
lexicographically first), that contract dissolves and downstream
incrementality is impossible regardless of how clever the resolver is.

Merge survivor selection is inherently arbitrary (CRMs punt it to a human),
so the tie-break serves engineering: **the entity with the most existing
mapping rows survives**, minimizing rewrites; entity_id breaks ties
deterministically.

### 2.4 Downstream tables are caches; the merge log is the invalidation stream

Materialized entity_ids in participants/traits/states are denormalized caches
of "resolve this identifier as of now." A merge is a cache-invalidation event.
The resolution log (§4.5) is the invalidation stream: downstream incremental
models re-emit exactly the rows whose entity_id appears as a
`previous_entity_id` in log entries newer than their watermark. The same
`repointed` rows double as an outbound merge/alias protocol for external
tools (Segment alias, Mixpanel merge, customer.io, …).

### 2.5 Splits are out of the incremental flow, by design

Everything above rests on monotonicity. Three things violate it: retroactive
noise filtering (an identifier's connection count crosses a threshold and its
historical edges get disqualified), data corrections, and deletion requests.
Removing an edge can shatter a component, and no summary kept from the
monotone world can answer "is there another path?" — this is the decremental
connectivity problem, fundamentally harder than incremental (union-find has
no un-union).

Position taken:

- **Merges** are incremental facts, handled every batch.
- **Splits** are rare, local, explicitly-targeted events, handled by
  re-resolving *one component from its raw edges* (the look-ahead/expansion
  algorithm, run on demand) or by full refresh. Never part of the standard
  dbt flow. This is why the raw edge table is retained even though the
  resolver never reads it again.
- **Global full refresh** is reserved for *rule changes* (normalization,
  edge-generation logic), where every component is suspect and nothing can be
  localized.

Consequently, incremental mode is **incompatible with edge autofiltering**
(`edge_quality.critical_autofilter` / `error_autofilter`): admit-then-revoke
filtering is anti-monotone. `create_identifier_edges` raises a compile error
if both are enabled. The monotone replacement — quarantine-on-entry, where an
identifier already known to be promiscuous never bridges anything — is future
work (§7).

### 2.6 Knowledge timeline vs. world timeline

Monotonicity is a claim about the **ingestion** timeline (`_ingested_at`),
not the event timeline (`occurred_at`). The identifier graph is atemporal:
an edge is a set-membership fact, and the partition is order-insensitive, so
out-of-order ingestion is harmless — a 2019 event arriving today produces
exactly the partition it would have produced arriving in 2019. Late data just
means a merge happens later than it could have.

Two consequences with teeth:

1. **Watermarks are always on `_ingested_at`, never `occurred_at`.** Filtering
   the delta by event time silently drops backfills forever.
2. Everything that *interprets* components (traits, states, attribution)
   still orders by `occurred_at`, read off the rows — so those semantics are
   also arrival-order-independent.

## 3. The algorithm (one incremental run of the resolver)

State carried between runs: the resolved mapping itself (`{{ this }}`).
Nothing else is read from prior runs.

1. **Delta.** Identifier rows and edges with `_ingested_at >` the max
   watermark already absorbed into `{{ this }}`. Both are needed: a
   single-identifier event produces no edge but must still mint or accrete.
2. **Lookup.** Left-join every delta identifier against the prior mapping.
   Each node is *known* (has an entity_id) or *new*.
3. **Contract.** Build the dirty graph: node key = entity_id for known
   identifiers (the super-node), a synthetic `unresolved|type|value` key for
   new ones. Rewrite delta edges in node keys; edges internal to one existing
   entity become self-loops and drop out.
4. **Connected components** over the contracted graph — Jinja-unrolled
   min-label propagation, adapter-generic (plain joins; the graph is tiny).
   Real CC is required, not per-edge classification: within one batch, new
   identifier X can link entity A in one event and new identifier Y in
   another, and Y can link entity B — A∪X∪Y∪B is discoverable only by
   traversal. Iteration count only needs to cover within-batch chain
   diameter (prior components are single nodes), so small constants suffice.
5. **Classify** each resulting component by distinct prior entity_ids:
   - **0** → born: mint an id from the lexicographically-first identifier
     (same format the full path would assign a brand-new component).
   - **1** → accretion: the entity keeps its id.
   - **≥2** → merge: biggest-entity-wins survivor; *every* mapping row of
     every loser is re-pointed to the survivor (the whole component moves,
     including identifiers not in this batch).
6. **Emit the change-set**: new identifier rows (`born` / `accreted`) plus
   re-pointed loser rows (`repointed`, with `previous_entity_id`). Untouched
   entities never appear; dbt's merge never touches their rows.
7. **Re-emit observations** (`reobserved`): known identifiers seen in this
   batch whose entity didn't change get their existing mapping row re-emitted
   unchanged except for the reason and a fresh watermark. This carries no new
   information — it exists so that *every* processed delta row is covered by
   an emitted row bearing the batch watermark. Without it, a steady-state
   batch of already-known identifiers (the common case: the same people
   showing up again) would emit nothing, `max(resolved_at_watermark)` would
   stagnate, and every subsequent run would re-scan an ever-growing delta.
   Bounded by batch size; excluded from the resolution log.
8. **Stamp** every emitted row with `resolved_at_watermark = max(_ingested_at)`
   of the delta — deterministic (no `now()`), so re-runs are idempotent and
   the log has a clean cursor. Steps 6–8 together guarantee the watermark
   advances past the full processed delta on every non-empty run.

Properties that fall out: empty delta → no-op; duplicate/overlapping batches
→ no-ops (safe under at-least-once delivery and sloppy lookbacks); first run
and `--full-refresh` see empty state and degrade to a full resolution;
multi-batch merge chains (A absorbs B today, C absorbs A tomorrow) compose
because the mapping is always fully compressed.

## 4. dbt implementation

### 4.1 Feature flag

```yaml
vars:
  nexus:
    incremental:
      enabled: true   # default false
```

`nexus_incremental_enabled()` reads the flag;
`nexus_incremental_materialization()` returns `'incremental'` or the previous
default `'table'`, so each model file serves both modes. With the flag off,
compiled SQL is unchanged except for three additive provenance columns on the
resolved tables (§4.4).

### 4.2 No batch coordination

There is no shared batch id and no orchestration requirement. Every
incremental model defines its own delta as "input rows with `_ingested_at`
greater than the max I've already absorbed," checked against its own
`{{ this }}`. Models can run at different cadences, retry, or overlap;
monotonicity + idempotency make the worst case a redundant no-op.

### 4.3 Upstream plumbing

- `process_entity_identifiers` / `nexus_entity_identifiers`: now emits
  `_ingested_at` and appends only rows past the watermark in incremental
  mode. In incremental mode every ER-feeding source MUST expose the column —
  the build fails at compile time naming offenders (§4.7); the legacy
  `occurred_at` fallback survives only in table mode, where no watermark
  exists to corrupt.
- `create_identifier_edges` / `nexus_entity_identifiers_edges`: emits
  `_ingested_at` and `edge_uniqueness_hash`; in incremental mode derives
  edges only from new identifier rows (both endpoints of an edge arrive with
  the same event, so filtering rows filters whole edges) and anti-joins
  against existing hashes so a re-derived edge keeps its first sighting's
  `_ingested_at` (re-inserting would be a harmless but wasteful reprocess).
  Raises a compile error if incremental mode is combined with edge
  autofiltering (§2.5).

### 4.4 The resolver

`nexus_resolved_person_identifiers` / `nexus_resolved_group_identifiers`:

- **Full path** (table mode, first run, `--full-refresh`): the existing
  adapter-dispatched whole-graph traversal, now emitting three additional
  columns: `resolution_reason='full_resolution'`, `previous_entity_id=null`,
  and `resolved_at_watermark=` the global ingestion high-water mark at
  resolution time (so a subsequent incremental run starts exactly where the
  full resolution left off).
- **Incremental path**: `incremental_resolve_identifiers()` implements §3.
  `unique_key=['identifier_type','identifier_value']`; the merge strategy
  overwrites re-pointed rows in place. The macro is adapter-generic — the
  contracted graph is small enough that plain joins work everywhere, so the
  per-warehouse dispatch surface does not grow.

### 4.5 The resolution log

`nexus_resolution_log` (built only when the flag is on): append-only record
of every resolution decision, unioned across ER entity types, cursored on
`resolved_at_watermark`. This is the merge log, the downstream invalidation
stream, and the outbound alias protocol, in one artifact. `reobserved` rows
never enter it — observation is watermark bookkeeping, not a resolution
decision (and the cursor stays safe across reobserved-only batches because
batch watermarks are strictly increasing).

It is also the **first table in the package that cannot be rebuilt from
source data**: it records the history of what the pipeline concluded and
when, which is path-dependent on ingestion order. It is protected with
`full_refresh: false`; a full refresh of the resolver appends a new
`full_resolution` epoch rather than erasing history. Treat it as
system-of-record: back it up, never truncate casually.

Caveat: the log captures the mapping's state per run of the log model. If the
resolver runs multiple times before the log runs, intermediate hops for rows
changed twice are collapsed into the latest state. Run the log in the same
DAG invocation as the resolver (the default `dbt run` does).

### 4.6 What is deliberately NOT incremental yet

- **Downstream models** (participants, traits, states, entities): still full
  rebuilds over now-complete mappings — unchanged semantics. Incrementalizing
  them is the natural next phase; each one's delta is (new events) ∪ (rows
  whose entity_id appears in new `repointed` log entries). The wide
  `nexus_entities` pivot may stay a full rebuild indefinitely: its columns are
  discovered at compile time (dynamic schema), and the entity dimension is
  small next to the event-grain tables. Spend the incrementality budget where
  the rows are.
- **Source event-log models**: the *final* source models for gmail and
  google_calendar (`<source>_events`, `_entity_identifiers`,
  `_entity_traits`, `_relationship_declarations`) are now flag-gated
  incrementals — watermark append via `nexus_incremental_source_filter()`
  with a unique-key merge (re-synced upstream records overwrite their prior
  row) and an incremental-only batch dedup (warehouse merges reject
  duplicate keys within one batch). The base/intermediate layers underneath
  stay full rebuilds: that is where the raw-scan cost still lives, and
  incrementalizing them (especially the windowed dedup in `*_base_dedupped`)
  is a separate cost project. Other package sources (segment) and
  consumer-local sources follow the same recipe when wanted.
- **Quarantine / connection-count maintenance** (§7).

### 4.7 Known edge cases and assumptions

- **Watermark boundary ties.** The delta predicate is strictly `>`. If a
  loader stamps many rows with one `_ingested_at` and dbt runs mid-load, the
  stragglers sharing the boundary timestamp are skipped. Mitigations: run
  after loads complete, or add a lookback (reprocessing is idempotent).
  A configurable lookback is future work.
- **`_ingested_at` is a hard, all-or-nothing requirement across ER
  sources.** The core union keeps ONE watermark across every
  `entities: true` source, so the discipline is collective: a source
  emitting rows *behind* the shared watermark silently loses them (the
  backfill case — why an `occurred_at` fallback is forbidden in incremental
  mode), and a source stamping *ahead* of real time (`now()` stamps, clock
  skew) drags the watermark past every OTHER source's upcoming rows.
  Enforcement is two-layered: `process_entity_identifiers` fails at compile
  time naming any enabled ER source whose identifiers model lacks the
  column, and the packaged
  `test_incremental_sources_ingested_at_not_null` test catches null values
  at the sources (a null would fail the watermark predicate and vanish
  silently — the core table can never witness its own missing rows).
  Note this is about *timestamp discipline*, not materialization: a source
  model may stay a full-rebuild `table` forever; only its rows' stamps must
  be truthful. For static/seed sources with no loader timestamp, stamp a
  **data-vintage literal** (e.g. the export date, held in a var) and bump it
  when the data changes — every row is re-offered and monotonicity makes
  that an idempotent no-op for already-absorbed rows. Package sources:
  gmail/google_calendar comply; segment does not yet (`segment_events`
  stamps `current_timestamp()` and the identifiers unpivot drops the column
  entirely) — enabling segment with incremental mode fails loudly until its
  real `loaded_at`/`received_at` is threaded through.
- **The edges table's watermark can idle on pair-free batches.** A batch
  containing only single-identifier events produces no edges, so the edge
  model's own high-water mark doesn't advance and those identifier rows are
  re-scanned by the edge self-join on subsequent runs until a batch with
  pairs arrives. Benign: the anti-join makes re-derivation a no-op, rows from
  different events never share an `edge_id` (no spurious cross-batch edges),
  and the resolver's watermark advances independently via `reobserved` rows.
- **`max_recursion` semantics change** in incremental mode: it bounds
  within-batch chain diameter over the contracted graph (small), not
  historical component diameter. The default of 5 is generous; a chain of >5
  distinct entities/identifiers linked in one batch would under-merge (the
  next batch touching them heals it, but don't rely on that — raise the var
  if batches are huge).
- **BigQuery pruning needs literals and a rebuild.** Watermark predicates
  are inlined as timestamp literals fetched at render time
  (`nexus_incremental_watermark_literal`) because BigQuery only reliably
  prunes partitions on constants — a scalar-subquery watermark forces a
  full scan every run. The incremental tables carry
  `partition_by(month(_ingested_at | resolved_at_watermark))` +
  `cluster_by(merge keys)` via the standard `nexus_bq_partition_by` /
  `nexus_cluster_by` toggles (no-ops off BigQuery). Note dbt cannot
  repartition an existing table in place: tables built before these configs
  keep their old layout (and its full-scan merges) until a one-time
  `--full-refresh` rebuilds them — the upgrade guards do NOT catch this
  case since no columns are missing. Measured motivation: a zero-row
  steady-state merge into the unpartitioned SRT identifiers table scanned
  ~280 MiB.
- **Full refresh renumbers.** By design (§2.1). Downstream systems holding
  entity_ids must treat a full refresh as an id-migration event; the log's
  new epoch is the migration record.

## 5. Rollout: no fork

Recommended path for working this into consumer projects over several cycles:

1. The flag defaults **off**; merged to main, the package is inert. No fork
   and no long-lived divergence needed — dbt consumers pin packages by git
   revision, so a consumer opts into a testing cycle with:

   ```yaml
   packages:
     - git: https://github.com/slide-rule-tech/dbt-nexus.git
       revision: <branch-or-tag>
   ```

   and opts into the behavior (independently!) with the var. Two consumers on
   the same revision can run different modes.
2. First enablement in a consumer starts with `dbt run --full-refresh` of the
   resolver subgraph (establishes the epoch), then normal runs.
3. Keep a scheduled partition-equality check (§6.3) during the trust-building
   period.

Forking would only make sense to escape upstream review/permissions — it buys
nothing here and costs continuous rebasing.

## 6. Testing harness (design — not yet implemented)

The core difficulty: incremental correctness is a property of **run
sequences**, not states. dbt's native tests assert post-run state; something
outside dbt must drive the sequence. Three layers:

### 6.1 dbt unit tests (dbt ≥ 1.8) — single-run resolver logic

dbt unit tests can mock `this` as a fixture and force `is_incremental()` via
macro overrides. "Given this prior mapping and these delta rows, the model
emits exactly this change-set" becomes declarative YAML — no warehouse,
milliseconds. One fixture per classification case: born singleton, accretion,
simple merge, within-batch chain (A–X, X–Y, Y–B must unify — exercises the CC
step, not just lookups), survivor selection (bigger entity wins; entity_id
tie-break), loser re-emission includes identifiers absent from the batch.

### 6.2 Multi-run scenario harness on DuckDB — sequence properties

A small script (~50 lines: bash or pytest) plus scenario seeds, against a
throwaway `.duckdb` file. The trick that keeps scenarios declarative is a
**simulated ingestion clock**: the entire scenario lives in one seed with an
`_ingested_at` column; a test-only source shim gates rows with
`where _ingested_at <= var('simulated_now')`; the harness advances the clock:

```
dbt seed
dbt run  --vars 'simulated_now: 2024-01-01'   # batch 1
dbt test                                       # invariants at t1
dbt run  --vars 'simulated_now: 2024-01-02'   # batch 2
dbt test                                       # invariants at t2
```

Scenario list (each is one seed + a clock sequence + expected partitions):

- singleton birth; accretion; simple two-entity merge
- merge chain within a batch; merge chain **across** batches
  (A absorbs B, then C absorbs A — verifies compression composes)
- duplicate batch re-ingestion → byte-identical state (idempotency)
- out-of-order / late arrival → same partition as in-order
- empty batch → no-op
- **property test**: replay the same seed under different batch slicings
  (one big batch, daily, shuffled) and assert identical partitions — this
  tests the order-insensitivity theorem itself, cheaply

Invariants after every step are plain dbt data tests (they ARE state
assertions):

- **partition equality**: a shadow model full-resolves the clock-visible
  slice from scratch; compare **component memberships** (sets of identifiers
  grouped together), ignoring entity_ids — test the theorem, not the
  arbitrary bookkeeping
- every identifier maps to exactly one live entity_id; no mapping row points
  at an entity_id that appears as a `previous_entity_id` loser
- log is append-only and monotone in `resolved_at_watermark`; every
  `repointed` mapping state has a matching log entry
- id format parity: born ids match the full path's format

### 6.3 Production invariant tests (shipped in the package)

The partition-equality and mapping-hygiene checks packaged as generic tests,
run on a schedule against real data. This converts "trust the incremental
logic" into a monitored property and is what makes full refreshes rare rather
than a weekly safety ritual. The classic failure mode it catches: a watermark
bug silently skipping rows, which no single-run test can see.

### 6.4 Where it lives

An `integration_tests/` sub-project inside this repo (the dbt-utils pattern:
its `packages.yml` installs the package via `local: ..`). That is the
"consumer project" — it catches consumed-as-a-package failures (var wiring,
source indirection) without a separate repo. The simulated-clock source shims
belong there, not in package code: a real consumer must never inherit a
`simulated_now` gate. DuckDB is the target for the inner loop (already
supported via `install_duckdb_compat`); a thin nightly cross-adapter smoke
run on BigQuery/Snowflake covers dialect quirks the algorithm's plain joins
mostly avoid.

## 7. Future work

- **Quarantine-on-entry noise filtering**: an incrementally-maintained
  per-identifier connection-count aggregate; identifiers crossing thresholds
  are quarantined *before* their edges enter the graph (monotone-safe:
  admitting late merges; revoking never happens incrementally). Requires the
  resolver's lookup to treat quarantined identifiers as known-but-non-bridging.
- **Downstream incrementalization** off the resolution log (§4.6).
- **Split surgery tooling**: an operator-invoked routine that re-expands one
  component from raw edges, re-resolves it, and emits `split` log entries.
- **Outbox consumers**: per-consumer cursors over the resolution log for
  webhooks / reverse-ETL merge calls (trait-change events belong to the same
  pattern once traits are incremental).
- **Configurable watermark lookback** for loaders with coarse `_ingested_at`.
- **Per-source watermarks in the core union**, containing a lagging or
  clock-skewed source's blast radius to itself instead of the shared clock —
  only fully effective if also threaded through the resolver's watermark,
  which needs per-source bookkeeping in the mapping; until then, truthful
  wall-clock stamps are the enforced assumption.
- **Segment `_ingested_at` compliance**: thread `loaded_at`/`received_at`
  through `segment_events` and the identifiers unpivot, validated against a
  real segment warehouse.
