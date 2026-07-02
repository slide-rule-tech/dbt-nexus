#!/usr/bin/env python3
"""Multi-run scenario runner for the dbt-nexus incremental identity
resolution harness.

Why a script at all: incremental correctness is a property of run SEQUENCES,
not states. dbt tests assert post-run state; this runner is the only thing in
the stack that can observe two runs — so the sequence properties (idempotency,
id stability, log append-only, watermark advancement) live here, and the
state invariants (partition equality vs a from-scratch shadow resolution,
mapping hygiene, log shape) live in tests/ and run after every step.

Mechanics (docs/incremental-identity-resolution.md §6.2):
  - the whole scenario lives in seeds/it_identifier_rows.csv with an
    _ingested_at column (the simulated ingestion clock)
  - each scenario gets a fresh DuckDB file under target/scenarios/
  - steps = the scenario's distinct _ingested_at values, ascending; each step
    re-runs dbt with it_now advanced, so the package's incremental models see
    one batch of "newly ingested" rows per run
  - step 1 is the epoch: the resolver's full path (is_incremental() is false
    on the empty database) — exactly how a real consumer's first build works

Usage:
    python3 integration_tests/run.py            # all scenarios
    python3 integration_tests/run.py accretion  # one scenario
    python3 integration_tests/run.py --keep-going
The per-scenario databases are left behind for inspection:
    duckdb integration_tests/target/scenarios/<scenario>.duckdb
"""

import argparse
import csv
import json
import os
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

IT_DIR = Path(__file__).resolve().parent


def _find_dbt():
    """dbt from PATH, else the monorepo's nexus-python venv, else a real error."""
    exe = shutil.which("dbt")
    if exe:
        return exe
    venv_dbt = IT_DIR.parents[1] / "nexus-python" / "bin" / "dbt"
    if venv_dbt.exists():
        return str(venv_dbt)
    sys.exit(
        "dbt not found on PATH (and no ../../nexus-python venv). Activate an "
        "env with dbt + dbt-duckdb, e.g.:\n"
        "  source ../../nexus-python/bin/activate"
    )


DBT_EXE = _find_dbt()
SEED_CSV = IT_DIR / "seeds" / "it_identifier_rows.csv"
SCENARIO_DB_DIR = IT_DIR / "target" / "scenarios"

RUN_SELECT = [
    "--select",
    "+nexus_resolution_log",
    "+it_shadow_resolved_person",
    "+it_shadow_resolved_group",
]
TEST_SELECT = ["--select", "tag:it_invariant"]

MAPPING_TABLES = {
    "person": "nexus_resolved_person_identifiers",
    "group": "nexus_resolved_group_identifiers",
}

# Per-scenario expectations, asserted after the FINAL step. Log reason counts
# exclude the 'full_resolution' epoch rows (step 1 is always the full path).
# 'same_entity' lists identifier groups ("type|value") that must share one
# entity; 'distinct_entities' lists identifiers that must all differ.
EXPECT = {
    "birth_singleton": {
        "entities": {"person": 2},
        "log": {"born": 1, "accreted": 0, "repointed": 0},
        "distinct_entities": {"person": ["email|alice@bs.test", "email|bob@bs.test"]},
    },
    "accretion": {
        "entities": {"person": 1},
        "log": {"born": 0, "accreted": 1, "repointed": 0},
        "same_entity": {
            "person": [["email|a@acc.test", "anonymous_id|acc-anon-1", "email|c@acc.test"]]
        },
        # extra clock step past the last data: must be a clean no-op
        "empty_final_step": True,
    },
    "simple_merge": {
        "entities": {"person": 1},
        "log": {"born": 0, "accreted": 0, "repointed": 2},
        "same_entity": {
            "person": [[
                "email|m1@sm.test", "anonymous_id|sm-anon-1",
                "email|m2@sm.test", "anonymous_id|sm-anon-2",
            ]]
        },
    },
    "chain_within_batch": {
        # three prior entities fused via two brand-new bridge identifiers,
        # all in one batch — exercises real CC on the contracted graph
        "entities": {"person": 1},
        "log": {"born": 0, "accreted": 2, "repointed": 4},
    },
    "chain_across_batches": {
        # A absorbs B, then the merged entity absorbs C in a later batch —
        # verifies the mapping stays fully compressed across merges
        "entities": {"person": 1},
        "log": {"born": 0, "accreted": 0, "repointed": 4},
    },
    "reobserved_watermark": {
        # batch 2 re-observes known identifiers only: no resolution changes,
        # but the watermark MUST advance (regression test for the
        # 'reobserved' fix); batch 3 births a singleton
        "entities": {"person": 2},
        "log": {"born": 1, "accreted": 0, "repointed": 0},
        "watermark_advances_every_step": True,
    },
    "out_of_order": {
        # batch 2 delivers an event that OCCURRED before batch 1's event:
        # ingestion-time watermarks must not care
        "entities": {"person": 1},
        "log": {"born": 0, "accreted": 1, "repointed": 0},
        "same_entity": {
            "person": [["email|o1@ooo.test", "anonymous_id|ooo-anon-1", "email|o2@ooo.test"]]
        },
    },
    "groups_merge": {
        # group-type merge, plus a person identifier riding in the same event
        # (cross-entity-type edges must not bleed between resolvers)
        "entities": {"group": 1, "person": 1},
        "log": {"born": 1, "accreted": 0, "repointed": 2},
        "same_entity": {
            "group": [["domain|xg.test", "name|x-corp", "domain|yg.test", "name|y-corp"]]
        },
    },
}

FAR_FUTURE = "2030-01-01 00:00:00"


class Failure(Exception):
    pass


def log(msg, indent=0):
    print("  " * indent + msg, flush=True)


def read_scenarios():
    """scenario -> sorted list of distinct _ingested_at strings."""
    steps = defaultdict(set)
    with open(SEED_CSV) as f:
        for row in csv.DictReader(f):
            steps[row["scenario"]].add(row["_ingested_at"])
    return {s: sorted(ts) for s, ts in steps.items()}


def dbt(args, db_path, extra_vars=None, quiet=True):
    cmd = [DBT_EXE, "--no-use-colors", *args]
    if extra_vars:
        cmd += ["--vars", json.dumps(extra_vars)]
    env = os.environ.copy()
    env["DBT_PROFILES_DIR"] = str(IT_DIR)
    env["IT_DB_PATH"] = str(db_path)
    proc = subprocess.run(cmd, cwd=IT_DIR, env=env, capture_output=True, text=True)
    if proc.returncode != 0:
        tail = "\n".join((proc.stdout + proc.stderr).splitlines()[-40:])
        raise Failure(f"dbt {' '.join(args[:2])} failed:\n{tail}")
    return proc.stdout


def query(db_path, sql):
    import duckdb

    con = duckdb.connect(str(db_path), read_only=True)
    try:
        return con.execute(sql).fetchall()
    finally:
        con.close()


def snapshot(db_path):
    """Full observable state: mapping per type, log rows, max watermark."""
    state = {"mapping": {}, "log": set(), "log_rows": [], "wm": {}}
    for etype, table in MAPPING_TABLES.items():
        rows = query(
            db_path,
            f"select identifier_type || '|' || identifier_value, {etype}_id "
            f"from main.{table}",
        )
        state["mapping"][etype] = dict(rows)
        wm = query(db_path, f"select max(resolved_at_watermark) from main.{table}")
        state["wm"][etype] = wm[0][0]
    state["log_rows"] = query(
        db_path,
        "select resolution_id, entity_type, resolution_reason, entity_id, "
        "previous_entity_id from main.nexus_resolution_log order by 1",
    )
    state["log"] = {r[0] for r in state["log_rows"]}
    return state


def repointed_map(db_path, etype):
    """previous_entity_id -> entity_id from all repointed log rows."""
    rows = query(
        db_path,
        "select previous_entity_id, entity_id from main.nexus_resolution_log "
        f"where resolution_reason = 'repointed' and entity_type = '{etype}'",
    )
    return dict(rows)


def check(cond, msg):
    if not cond:
        raise Failure(msg)


def assert_sequence_invariants(prev, curr, db_path, scenario, step_label):
    """Invariants relating consecutive steps — the part dbt tests can't see."""
    # log is append-only
    lost = prev["log"] - curr["log"]
    check(not lost, f"[{step_label}] log lost rows (not append-only): {sorted(lost)[:5]}")

    # id stability: an identifier's entity changes ONLY via a logged repoint
    for etype in MAPPING_TABLES:
        repoints = repointed_map(db_path, etype)
        for ident, old_entity in prev["mapping"][etype].items():
            new_entity = curr["mapping"][etype].get(ident)
            check(
                new_entity is not None,
                f"[{step_label}] {etype} identifier disappeared from mapping: {ident}",
            )
            if new_entity != old_entity:
                check(
                    repoints.get(old_entity) == new_entity,
                    f"[{step_label}] {etype} {ident} moved {old_entity} -> "
                    f"{new_entity} without a matching repointed log entry",
                )


def assert_expectations(exp, final, db_path, scenario):
    for etype, want in exp.get("entities", {}).items():
        got = len(set(final["mapping"][etype].values()))
        check(got == want, f"expected {want} {etype} entities, got {got}")

    want_log = exp.get("log")
    if want_log:
        rows = query(
            db_path,
            "select resolution_reason, count(*) from main.nexus_resolution_log "
            "where resolution_reason != 'full_resolution' group by 1",
        )
        got_log = {r: 0 for r in ("born", "accreted", "repointed")}
        got_log.update(dict(rows))
        for reason, want in want_log.items():
            check(
                got_log.get(reason, 0) == want,
                f"expected log {reason}={want}, got {got_log.get(reason, 0)} "
                f"(full log: {got_log})",
            )

    for etype, groups in exp.get("same_entity", {}).items():
        m = final["mapping"][etype]
        for group in groups:
            entities = {m.get(i) for i in group}
            check(
                len(entities) == 1 and None not in entities,
                f"{etype} identifiers {group} should share one entity, got {entities}",
            )

    for etype, idents in exp.get("distinct_entities", {}).items():
        m = final["mapping"][etype]
        entities = [m.get(i) for i in idents]
        check(
            None not in entities and len(set(entities)) == len(idents),
            f"{etype} identifiers {idents} should all be distinct entities, got {entities}",
        )


def run_scenario(scenario, steps):
    db_path = SCENARIO_DB_DIR / f"{scenario}.duckdb"
    db_path.parent.mkdir(parents=True, exist_ok=True)
    for stale in (db_path, Path(str(db_path) + ".wal")):
        if stale.exists():
            stale.unlink()

    exp = EXPECT.get(scenario, {})
    log(f"scenario: {scenario} ({len(steps)} steps)")

    dbt(["seed"], db_path, {"it_scenario": scenario, "it_now": steps[0]})

    prev = None
    for n, ts in enumerate(steps, start=1):
        step_vars = {"it_scenario": scenario, "it_now": ts}
        label = f"{scenario} step {n}/{len(steps)} @ {ts}"
        dbt(["run", *RUN_SELECT], db_path, step_vars)
        dbt(["test", *TEST_SELECT], db_path, step_vars)
        curr = snapshot(db_path)
        if prev is not None:
            assert_sequence_invariants(prev, curr, db_path, scenario, label)
            if exp.get("watermark_advances_every_step"):
                for etype in ("person",):
                    check(
                        curr["wm"][etype] > prev["wm"][etype],
                        f"[{label}] watermark did not advance: "
                        f"{prev['wm'][etype]} -> {curr['wm'][etype]}",
                    )
        log(f"step {n}/{len(steps)} @ {ts}: run + tests green", 1)
        prev = curr

    final_vars = {"it_scenario": scenario, "it_now": steps[-1]}

    # idempotency: re-running the final step must change nothing at all
    dbt(["run", *RUN_SELECT], db_path, final_vars)
    rerun = snapshot(db_path)
    check(
        rerun["mapping"] == prev["mapping"] and rerun["log"] == prev["log"],
        "re-running the final step changed state (not idempotent)",
    )
    log("idempotent re-run: state unchanged", 1)

    # optional empty batch: advance the clock past all data — clean no-op
    if exp.get("empty_final_step"):
        dbt(["run", *RUN_SELECT], db_path, {"it_scenario": scenario, "it_now": FAR_FUTURE})
        dbt(["test", *TEST_SELECT], db_path, {"it_scenario": scenario, "it_now": FAR_FUTURE})
        empty = snapshot(db_path)
        check(
            empty["mapping"] == prev["mapping"] and empty["log"] == prev["log"],
            "empty batch changed state",
        )
        log("empty batch: clean no-op", 1)

    assert_expectations(exp, prev, db_path, scenario)
    log("expectations met ✓", 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("scenarios", nargs="*", help="subset of scenarios to run")
    ap.add_argument("--keep-going", action="store_true", help="run all even after a failure")
    args = ap.parse_args()

    all_scenarios = read_scenarios()
    selected = args.scenarios or sorted(all_scenarios)
    unknown = [s for s in selected if s not in all_scenarios]
    if unknown:
        sys.exit(f"unknown scenario(s): {unknown}; available: {sorted(all_scenarios)}")

    missing_expect = [s for s in selected if s not in EXPECT]
    if missing_expect:
        log(f"note: no EXPECT entry for {missing_expect} — invariants only")

    if not (IT_DIR / "dbt_packages" / "nexus").exists():
        log("installing packages (dbt deps)…")
        dbt(["deps"], SCENARIO_DB_DIR / "_deps.duckdb")

    failures = {}
    for scenario in selected:
        try:
            run_scenario(scenario, all_scenarios[scenario])
        except Failure as e:
            failures[scenario] = str(e)
            log(f"FAILED: {e}", 1)
            if not args.keep_going:
                break

    log("")
    if failures:
        log(f"✗ {len(failures)}/{len(selected)} scenario(s) failed: {sorted(failures)}")
        sys.exit(1)
    log(f"✓ all {len(selected)} scenario(s) green")
    log(f"  inspect: duckdb {SCENARIO_DB_DIR}/<scenario>.duckdb")


if __name__ == "__main__":
    main()
