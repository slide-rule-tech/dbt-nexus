{% macro finalize_entities() %}

with resolved_traits as (
  select * from {{ ref('nexus_resolved_entity_traits') }}
),

-- Get all distinct entity IDs from all entity types
all_entities as (
    {# Support both new unified config and legacy variable #}
    {% set entity_types = var('nexus', {}).get('entity_types') or var('nexus_entity_types', ['person', 'group']) %}
    {% for entity_type in entity_types %}
        select
            {{ entity_type }}_id as entity_id,
            '{{ entity_type }}' as entity_type
        from {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }}
        {% if not loop.last %}
        union all
        {% endif %}
    {% endfor %}
),

distinct_entities as (
  select distinct
    entity_id,
    entity_type
  from all_entities
),

-- Get timestamps from entity_identifiers joined with resolved identifiers for _created_at
entity_created_timestamps as (
  {% set entity_types = var('nexus', {}).get('entity_types') or var('nexus_entity_types', ['person', 'group']) %}
  {% for entity_type in entity_types %}
  select
    ri.{{ entity_type }}_id as entity_id,
    min(ei.occurred_at) as _created_at
  from {{ ref('nexus_entity_identifiers') }} ei
  inner join {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }} ri
    on ei.identifier_value = ri.identifier_value
    and ei.identifier_type = ri.identifier_type
  where ei.entity_type = '{{ entity_type }}'
    and ei.occurred_at is not null
  group by ri.{{ entity_type }}_id
  {% if not loop.last %}
  union all
  {% endif %}
  {% endfor %}
),

-- Get timestamps from resolved traits for _updated_at
entity_updated_timestamps as (
  select
    entity_id,
    max(occurred_at) as _updated_at
  from resolved_traits
  where occurred_at is not null
  group by entity_id
),

-- Get edge timestamps for _last_merged_at
-- Calculate directly from nexus_entity_identifiers where edge_id exists (indicating identifiers merged in an event)
-- Use event_id to join with events to get the timestamp when the merge occurred
entity_edges_with_timestamps as (
  {% set entity_types = var('nexus', {}).get('entity_types') or var('nexus_entity_types', ['person', 'group']) %}
  {% for entity_type in entity_types %}
  select
    ri.{{ entity_type }}_id as entity_id,
    e.occurred_at
  from {{ ref('nexus_entity_identifiers') }} ei
  inner join {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }} ri
    on ei.identifier_value = ri.identifier_value
    and ei.identifier_type = ri.identifier_type
  inner join {{ ref('nexus_events') }} e
    on ei.event_id = e.event_id
  where ei.entity_type = '{{ entity_type }}'
    and ei.edge_id is not null
    and e.occurred_at is not null
  {% if not loop.last %}
  union all
  {% endif %}
  {% endfor %}
),

entity_last_merged_timestamps as (
  select
    entity_id,
    max(occurred_at) as _last_merged_at
  from entity_edges_with_timestamps
  where occurred_at is not null
  group by entity_id
),

-- Get interaction timestamps from entity_participants joined with events
entity_interaction_timestamps as (
  select
    entity_id,
    min(e.occurred_at) as first_interaction_at,
    max(e.occurred_at) as last_interaction_at
  from {{ ref('nexus_entity_participants') }} ep
  inner join {{ ref('nexus_events') }} e
    on ep.event_id = e.event_id
  where e.occurred_at is not null
  group by entity_id
),

-- Pivot traits
pivoted_traits as (
  {{ nexus.pivot_traits('nexus_resolved_entity_traits', 'entity_id', 'traits_') }}
)

-- Join distinct entity IDs with traits and timestamps
select
  e.entity_id,
  e.entity_type,
  t.*,
  current_timestamp() as _processed_at,
  coalesce(uct._updated_at, ect._created_at) as _updated_at,
  ect._created_at,
  elmt._last_merged_at,
  eit.last_interaction_at,
  eit.first_interaction_at
from distinct_entities e
left join pivoted_traits t on e.entity_id = t.traits_entity_id
left join entity_created_timestamps ect on e.entity_id = ect.entity_id
left join entity_updated_timestamps uct on e.entity_id = uct.entity_id
left join entity_last_merged_timestamps elmt on e.entity_id = elmt.entity_id
left join entity_interaction_timestamps eit on e.entity_id = eit.entity_id
{% endmacro %} 