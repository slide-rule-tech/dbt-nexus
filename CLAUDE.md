# dbt-nexus — agent instructions

`dbt-nexus` is the **public**, open-source Nexus dbt framework package.
Treat everything committed here as world-readable.

## Never commit client data or client-specific analyses to this repo

This is a **public** repository. Do **not** add customer/client data, results,
or client-specific analyses here — including anywhere under `analyses/`.

- `analyses/` must stay **empty**; it holds only `.gitkeep`. A CI check
  (`.github/workflows/guard-analyses.yml`) fails any commit that adds other
  files there.
- Client-specific analysis SQL/markdown, experiment results, lead/revenue
  figures, internal warehouse table or schema names, stakeholder names, and any
  customer confidential data belong in the **client's private repo**, or are
  run directly against the warehouse (e.g. via the Nexus MCP `query_warehouse`
  tool) — never persisted to this package.
- Only generic, non-client framework code (models, macros, tests, docs) belongs
  in `dbt-nexus`.

If you were asked to produce a client analysis, write it in the client's
**private** repository, not here. When in doubt, do not commit — ask first.
