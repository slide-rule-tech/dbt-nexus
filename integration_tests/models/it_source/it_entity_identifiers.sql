{{ config(materialized='table') }}

-- The simulated-clock source shim. The entire scenario lives in the seed;
-- this model exposes only the slice "ingested" so far. The runner advances
-- it_now across dbt invocations to simulate batches arriving. A table (not
-- incremental!) on purpose: it plays the role of the raw source, which the
-- package's incremental models watermark against.
select
    entity_identifier_id,
    event_id,
    edge_id,
    entity_type,
    identifier_type,
    identifier_value,
    role,
    source,
    occurred_at,
    _ingested_at
from {{ ref('it_identifier_rows') }}
where scenario = '{{ var("it_scenario") }}'
  and _ingested_at <= cast('{{ var("it_now") }}' as timestamp)
