{% macro incremental_resolve_identifiers(entity_type, identifiers_table, edges_table, max_iterations=5) %}

-- Incremental identity resolution via graph contraction.
--
-- See docs/incremental-identity-resolution.md for the full design. The short
-- version: because edges only ever arrive (monotonicity), previously resolved
-- components can never split -- they can only accrete new identifiers or
-- merge with each other. The prior identifier -> entity_id mapping ({{ this }})
-- is therefore a lossless summary of all prior connectivity: each resolved
-- component enters this run's graph as a single contracted "super-node", and
-- connected components run only over (touched super-nodes + new identifiers
-- + new edges). Cost scales with batch size, not history size. Old edges are
-- never re-read.
--
-- Per resulting component:
--   0 prior entity_ids  -> a new entity is born (id minted from the
--                          lexicographically-first identifier, same format
--                          as the full-resolution path)
--   1 prior entity_id   -> accretion; the entity keeps its id
--   2+ prior entity_ids -> merge; the entity with the most existing mapping
--                          rows survives (minimizes rewrites), all mapping
--                          rows of the losers are re-pointed to the survivor
--                          and recorded with resolution_reason='repointed'
--
-- The emitted rows are the change-set (new + re-pointed) plus 'reobserved'
-- re-emissions of known identifiers seen in this batch. Reobserved rows
-- carry no new information -- they exist so every processed delta row is
-- covered by an emitted row bearing the batch watermark, guaranteeing
-- max(resolved_at_watermark) advances even on change-free batches (otherwise
-- steady-state batches of already-known identifiers would re-scan an
-- ever-growing delta forever). Entities untouched by the batch never appear,
-- so dbt's merge never touches their rows.
--
-- Adapter-generic on purpose: the contracted graph is tiny, so plain joins
-- plus a Jinja-unrolled min-label propagation work on every warehouse -- no
-- recursive-CTE dialect quirks. `max_iterations` only needs to cover the
-- diameter of chains formed within ONE batch (not component diameter across
-- history -- prior components are single nodes here), so the default of 5 is
-- generous.

with prior_state as (
  select
    identifier_type,
    identifier_value,
    {{ entity_type }}_id as entity_id
  from {{ this }}
),

prior_watermark as (
  select coalesce(max(resolved_at_watermark), cast('1970-01-01' as timestamp)) as wm
  from {{ this }}
),

delta_identifiers as (
  select ei.*
  from {{ ref(identifiers_table) }} ei
  where ei.entity_type = '{{ entity_type }}'
    and ei.identifier_value is not null
    and ei._ingested_at > (select wm from prior_watermark)
),

batch_watermark as (
  select max(_ingested_at) as wm from delta_identifiers
),

delta_edges as (
  select e.*
  from {{ ref(edges_table) }} e
  where e.entity_type_a = '{{ entity_type }}'
    and e.entity_type_b = '{{ entity_type }}'
    and e._ingested_at > (select wm from prior_watermark)
),

-- Contraction: every distinct identifier in the batch becomes a graph node.
-- Known identifiers collapse onto their entity_id (the super-node); unknown
-- identifiers stand as themselves under a collision-proof synthetic key.
delta_nodes as (
  select
    d.identifier_type,
    d.identifier_value,
    p.entity_id,
    case
      when p.entity_id is not null then p.entity_id
      else 'unresolved|' || d.identifier_type || '|' || d.identifier_value
    end as node_key
  from (
    select distinct identifier_type, identifier_value
    from delta_identifiers
  ) d
  left join prior_state p
    on p.identifier_type = d.identifier_type
    and p.identifier_value = d.identifier_value
),

-- Batch edges rewritten in contracted terms. Both endpoints of a delta edge
-- are guaranteed to be delta identifiers (an edge's endpoints arrive with
-- the same event). Edges internal to one existing entity contract to
-- self-loops and drop out here.
contracted_edges as (
  select distinct
    na.node_key as node_a,
    nb.node_key as node_b
  from delta_edges e
  join delta_nodes na
    on na.identifier_type = e.identifier_type_a
    and na.identifier_value = e.identifier_value_a
  join delta_nodes nb
    on nb.identifier_type = e.identifier_type_b
    and nb.identifier_value = e.identifier_value_b
  where na.node_key != nb.node_key
),

sym_edges as (
  select node_a, node_b from contracted_edges
  union
  select node_b as node_a, node_a as node_b from contracted_edges
),

-- Min-label propagation over the contracted graph, unrolled at compile time.
labels_0 as (
  select distinct node_key, node_key as label
  from delta_nodes
)
{% for i in range(1, max_iterations + 1) %}
,
labels_{{ i }} as (
  select node_key, min(label) as label
  from (
    select node_key, label from labels_{{ i - 1 }}
    union all
    select e.node_a as node_key, l.label
    from sym_edges e
    join labels_{{ i - 1 }} l
      on l.node_key = e.node_b
  ) neighborhood
  group by node_key
)
{% endfor %}
,

nodes_labeled as (
  select
    dn.identifier_type,
    dn.identifier_value,
    dn.entity_id,
    fl.label
  from delta_nodes dn
  join labels_{{ max_iterations }} fl
    on fl.node_key = dn.node_key
),

-- Survivor selection for merges: the prior entity with the most existing
-- mapping rows wins (fewest rows re-pointed); entity_id breaks ties
-- deterministically.
prior_entity_sizes as (
  select
    {{ entity_type }}_id as entity_id,
    count(*) as n_rows
  from {{ this }}
  group by {{ entity_type }}_id
),

component_prior_entities as (
  select distinct label, entity_id
  from nodes_labeled
  where entity_id is not null
),

survivors as (
  select label, entity_id as survivor_entity_id
  from (
    select
      cpe.label,
      cpe.entity_id,
      row_number() over (
        partition by cpe.label
        order by coalesce(pes.n_rows, 0) desc, cpe.entity_id
      ) as rn
    from component_prior_entities cpe
    left join prior_entity_sizes pes
      on pes.entity_id = cpe.entity_id
  ) ranked
  where rn = 1
),

-- Components containing no prior entity mint a fresh id from their
-- lexicographically-first identifier -- identical in format to the id the
-- full-resolution path would assign a brand-new component.
minted as (
  select
    label,
    {{ create_nexus_id(entity_type, ['identifier_type', 'identifier_value']) }} as minted_entity_id
  from (
    select
      nl.label,
      nl.identifier_type,
      nl.identifier_value,
      row_number() over (
        partition by nl.label
        order by nl.identifier_type, nl.identifier_value
      ) as rn
    from nodes_labeled nl
    where not exists (
      select 1 from component_prior_entities cpe
      where cpe.label = nl.label
    )
  ) ranked
  where rn = 1
),

component_entity as (
  select
    labels.label,
    coalesce(s.survivor_entity_id, m.minted_entity_id) as entity_id,
    s.survivor_entity_id is not null as has_prior_entity
  from (select distinct label from nodes_labeled) labels
  left join survivors s on s.label = labels.label
  left join minted m on m.label = labels.label
),

-- Earliest occurrence per new identifier within the batch, mirroring the
-- full path's dedup rule (keep the row with the lowest edge_id).
delta_first_occurrence as (
  select identifier_type, identifier_value, event_id
  from (
    select
      identifier_type,
      identifier_value,
      event_id,
      row_number() over (
        partition by identifier_type, identifier_value
        order by edge_id
      ) as rn
    from delta_identifiers
  ) ranked
  where rn = 1
),

-- Change-set part 1: previously unknown identifiers.
new_identifier_rows as (
  select
    ce.entity_id,
    nl.identifier_type,
    nl.identifier_value,
    fo.event_id,
    case when ce.has_prior_entity then 'accreted' else 'born' end as resolution_reason,
    cast(null as {{ dbt.type_string() }}) as previous_entity_id
  from nodes_labeled nl
  join component_entity ce
    on ce.label = nl.label
  join delta_first_occurrence fo
    on fo.identifier_type = nl.identifier_type
    and fo.identifier_value = nl.identifier_value
  where nl.entity_id is null
),

-- Change-set part 2: merges. Every mapping row of every losing entity is
-- re-pointed to the survivor -- including identifiers that never appeared
-- in this batch (the whole component moves, not just the touched surface).
losers as (
  select distinct
    nl.entity_id as loser_entity_id,
    ce.entity_id as survivor_entity_id
  from nodes_labeled nl
  join component_entity ce
    on ce.label = nl.label
  where nl.entity_id is not null
    and nl.entity_id != ce.entity_id
),

repointed_rows as (
  select
    l.survivor_entity_id as entity_id,
    t.identifier_type,
    t.identifier_value,
    t.event_id,
    'repointed' as resolution_reason,
    t.{{ entity_type }}_id as previous_entity_id
  from {{ this }} t
  join losers l
    on l.loser_entity_id = t.{{ entity_type }}_id
),

-- Change-set part 3: watermark advancement. A batch whose identifiers are
-- all already known and produce no merges (the steady-state common case:
-- the same people showing up again) would emit nothing, so
-- max(resolved_at_watermark) would never advance and every subsequent run
-- would re-scan an ever-growing delta. Re-emit the existing mapping rows of
-- known identifiers observed in this batch -- unchanged except
-- resolution_reason='reobserved' and the fresh watermark. Bounded by batch
-- size. Excluded from nexus_resolution_log (observation is not a resolution
-- decision). Loser-entity rows are excluded here because repointed_rows
-- already re-emits them.
reobserved_rows as (
  select
    t.{{ entity_type }}_id as entity_id,
    t.identifier_type,
    t.identifier_value,
    t.event_id,
    'reobserved' as resolution_reason,
    cast(null as {{ dbt.type_string() }}) as previous_entity_id
  from {{ this }} t
  join delta_nodes dn
    on dn.identifier_type = t.identifier_type
    and dn.identifier_value = t.identifier_value
  where dn.entity_id is not null
    and not exists (
      select 1 from losers l
      where l.loser_entity_id = t.{{ entity_type }}_id
    )
),

changes as (
  select entity_id, identifier_type, identifier_value, event_id, resolution_reason, previous_entity_id
  from new_identifier_rows
  union all
  select entity_id, identifier_type, identifier_value, event_id, resolution_reason, previous_entity_id
  from repointed_rows
  union all
  select entity_id, identifier_type, identifier_value, event_id, resolution_reason, previous_entity_id
  from reobserved_rows
)

select
  {{ create_nexus_id(entity_type ~ '_identifier', ['entity_id', 'identifier_type', 'identifier_value']) }} as {{ entity_type }}_identifier_id,
  entity_id as {{ entity_type }}_id,
  event_id,
  identifier_type,
  identifier_value,
  false as realtime_processed,
  true as existing_{{ entity_type }},
  resolution_reason,
  previous_entity_id,
  (select wm from batch_watermark) as resolved_at_watermark
from changes

{% endmacro %}
