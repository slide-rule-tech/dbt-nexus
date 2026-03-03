{% macro finalize_entities() %}

{% set er_types = nexus.get_er_entity_types() %}
{% set non_er_types = nexus.get_non_er_entity_types() %}
{% set entity_config = nexus.get_entity_type_config() %}
{% set has_er = er_types | length > 0 %}
{% set has_non_er = non_er_types | length > 0 %}
{% set er_trait_names = [] %}
{% if has_er %}
  {% set er_trait_names_raw = dbt_utils.get_column_values(ref('nexus_resolved_entity_traits'), 'trait_name') | default([]) %}
  {% for trait_name in er_trait_names_raw %}
    {% do er_trait_names.append(trait_name | replace(' ', '_') | lower) %}
  {% endfor %}
{% endif %}
{% set non_er_trait_names = [] %}
{% if has_non_er %}
  {% for entity_type in non_er_types %}
    {% set type_config = entity_config[entity_type] %}
    {% set reg_model = type_config.get('registration_model') %}
    {% if reg_model %}
      {% set exclude_cols = ['entity_id', 'entity_type', 'source', 'source_id', '_registered_at', '_source_created_at', '_source_updated_at'] %}
      {% set cols = adapter.get_columns_in_relation(ref(reg_model)) %}
      {% for col in cols %}
        {% if col.name | lower not in exclude_cols %}
          {% do non_er_trait_names.append(col.name | lower) %}
        {% endif %}
      {% endfor %}
    {% endif %}
  {% endfor %}
{% endif %}

{% if has_er %}
with resolved_traits as (
  select * from {{ ref('nexus_resolved_entity_traits') }}
),
{% else %}
with
{% endif %}

all_entities as (
    {% if has_er %}
    {% for entity_type in er_types %}
        select
            {{ entity_type }}_id as entity_id,
            '{{ entity_type }}' as entity_type
        from {{ ref('nexus_resolved_' ~ entity_type ~ '_identifiers') }}
        {% if not loop.last or has_non_er %}
        union all
        {% endif %}
    {% endfor %}
    {% endif %}

    {% if has_non_er %}
    {% for entity_type in non_er_types %}
        {% set type_config = entity_config[entity_type] %}
        {% set reg_model = type_config.get('registration_model') %}
        {% if reg_model %}
        select
            entity_id,
            entity_type
        from {{ ref(reg_model) }}
        {% if not loop.last %}
        union all
        {% endif %}
        {% endif %}
    {% endfor %}
    {% endif %}
),

distinct_entities as (
  select distinct
    entity_id,
    entity_type
  from all_entities
),

{% if has_er %}
entity_created_timestamps as (
  {% for entity_type in er_types %}
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

entity_updated_timestamps as (
  select
    entity_id,
    max(occurred_at) as _updated_at
  from resolved_traits
  where occurred_at is not null
  group by entity_id
),

entity_edges_with_timestamps as (
  {% for entity_type in er_types %}
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
{% endif %}

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

{% if has_er %}
pivoted_traits as (
  {{ nexus.pivot_traits('nexus_resolved_entity_traits', 'entity_id', 'traits_') }}
),
{% endif %}

{% if has_non_er %}
{% for entity_type in non_er_types %}
{% set type_config = entity_config[entity_type] %}
{% set reg_model = type_config.get('registration_model') %}
{% if reg_model %}
{{ entity_type }}_registration as (
  select * from {{ ref(reg_model) }}
),
{% endif %}
{% endfor %}
{% endif %}

_placeholder as (select 1 as _p)

select
  e.entity_id,
  e.entity_type,
  {% if has_er %}
  {% for trait_name in er_trait_names %}
  {% if trait_name not in non_er_trait_names %}
  t.{{ trait_name }} as {{ trait_name }},
  {% endif %}
  {% endfor %}
  t.traits_entity_id,
  {% endif %}
  {% if has_non_er %}
  {% for entity_type in non_er_types %}
  {% set type_config = entity_config[entity_type] %}
  {% set reg_model = type_config.get('registration_model') %}
  {% if reg_model %}
  {% set exclude_cols = ['entity_id', 'entity_type', 'source', 'source_id', '_registered_at', '_source_created_at', '_source_updated_at'] %}
  {% set cols = adapter.get_columns_in_relation(ref(reg_model)) %}
  {% for col in cols %}
  {% if col.name | lower not in exclude_cols %}
  {% set output_col_name = col.name | lower %}
  {% if output_col_name in er_trait_names %}
  coalesce(cast(reg_{{ entity_type }}.{{ col.name }} as {{ dbt.type_string() }}), t.{{ output_col_name }}) as {{ output_col_name }},
  {% else %}
  reg_{{ entity_type }}.{{ col.name }} as {{ output_col_name }},
  {% endif %}
  {% endif %}
  {% endfor %}
  {% endif %}
  {% endfor %}
  {% endif %}
  current_timestamp() as _processed_at,
  {% if has_er and has_non_er %}
  coalesce(
    uct._updated_at, ect._created_at,
    {% for entity_type in non_er_types %}
    {% if entity_config[entity_type].get('registration_model') %}
    reg_{{ entity_type }}._source_updated_at,
    {% endif %}
    {% endfor %}
    cast(null as timestamp)
  ) as _updated_at,
  coalesce(
    ect._created_at,
    {% for entity_type in non_er_types %}
    {% if entity_config[entity_type].get('registration_model') %}
    reg_{{ entity_type }}._source_created_at,
    {% endif %}
    {% endfor %}
    cast(null as timestamp)
  ) as _created_at,
  elmt._last_merged_at,
  {% elif has_er %}
  coalesce(uct._updated_at, ect._created_at) as _updated_at,
  ect._created_at,
  elmt._last_merged_at,
  {% else %}
  coalesce(
    {% for entity_type in non_er_types %}
    {% if entity_config[entity_type].get('registration_model') %}
    reg_{{ entity_type }}._source_updated_at,
    {% endif %}
    {% endfor %}
    cast(null as timestamp)
  ) as _updated_at,
  coalesce(
    {% for entity_type in non_er_types %}
    {% if entity_config[entity_type].get('registration_model') %}
    reg_{{ entity_type }}._source_created_at,
    {% endif %}
    {% endfor %}
    cast(null as timestamp)
  ) as _created_at,
  cast(null as timestamp) as _last_merged_at,
  {% endif %}
  eit.last_interaction_at,
  eit.first_interaction_at
from distinct_entities e
{% if has_er %}
left join pivoted_traits t on e.entity_id = t.traits_entity_id
left join entity_created_timestamps ect on e.entity_id = ect.entity_id
left join entity_updated_timestamps uct on e.entity_id = uct.entity_id
left join entity_last_merged_timestamps elmt on e.entity_id = elmt.entity_id
{% endif %}
{% if has_non_er %}
{% for entity_type in non_er_types %}
{% set type_config = entity_config[entity_type] %}
{% if type_config.get('registration_model') %}
left join {{ entity_type }}_registration reg_{{ entity_type }}
  on e.entity_id = reg_{{ entity_type }}.entity_id
{% endif %}
{% endfor %}
{% endif %}
left join entity_interaction_timestamps eit on e.entity_id = eit.entity_id
{% endmacro %}
