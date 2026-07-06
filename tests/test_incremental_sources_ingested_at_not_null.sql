{{ config(enabled=nexus.nexus_incremental_enabled()) }}

{# Incremental mode requires every ER-feeding source to stamp a non-null
   _ingested_at on every row. Checked at the SOURCES rather than on
   nexus_entity_identifiers: a null there would fail the watermark predicate
   and be silently dropped from the core table, so the core table can never
   witness its own missing rows. Companion to the compile-time column check
   in process_entity_identifiers (that one catches the column missing
   entirely; this one catches null values in a column that exists). #}

{% set sources_config = var('nexus', {}).get('sources', {}) %}
{% set rels = [] %}
{% if sources_config %}
    {% for source_name, source_config in sources_config.items() %}
        {% if source_config.get('enabled') and source_config.get('entities') %}
            {% do rels.append(source_name) %}
        {% endif %}
    {% endfor %}
{% elif var('sources', none) %}
    {% for source in var('sources') %}
        {% if source.get('entities') %}
            {% do rels.append(source.name) %}
        {% endif %}
    {% endfor %}
{% endif %}

{% if rels %}
{% for s in rels %}
select
    '{{ s }}_entity_identifiers' as source_model,
    entity_identifier_id,
    identifier_type,
    occurred_at
from {{ ref(s ~ '_entity_identifiers') }}
where _ingested_at is null
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
{% else %}
select
    cast(null as varchar) as source_model,
    cast(null as varchar) as entity_identifier_id,
    cast(null as varchar) as identifier_type,
    cast(null as timestamp) as occurred_at
where 1 = 0
{% endif %}
