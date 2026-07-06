{{ config(materialized='table') }}

-- Minimal events model so the `it` source satisfies the package's
-- `events: true` contract (nexus_events refs it at parse time). One event
-- per edge_id in the visible slice. Not part of the ER test selection.
select
    event_id,
    min(occurred_at) as occurred_at,
    'it test event' as event_name,
    'synthetic event from the integration harness' as event_description,
    3 as significance,
    'test' as event_type,
    'it' as source,
    'it_identifier_rows' as source_table,
    min(_ingested_at) as _ingested_at,
    false as realtime_processed
from {{ ref('it_entity_identifiers') }}
group by event_id
