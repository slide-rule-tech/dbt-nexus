{% macro process_entity_identifiers() %}
    {# Collect relations to union - now sources provide unified entity_identifiers #}
    {% set relations_to_union = [] %}
    
    {# Support both new unified config and legacy list config #}
    {% set nexus_config = var('nexus', {}) %}
    {% set sources_config = nexus_config.get('sources', {}) %}
    
    {# New unified config pattern (nexus.sources dict) #}
    {% if sources_config %}
        {% for source_name, source_config in sources_config.items() %}
            {% if source_config.get('enabled') and source_config.get('entities') %}
                {% do relations_to_union.append(ref(source_name ~ '_entity_identifiers')) %}
            {% endif %}
        {% endfor %}
    {# Legacy config pattern (sources list) - backward compatibility #}
    {% elif var('sources', none) %}
        {% for source in var('sources') %}
            {% if source.get('entities') %}
                {% do relations_to_union.append(ref(source.name ~ '_entity_identifiers')) %}
            {% endif %}
        {% endfor %}
    {% endif %}

    {# _ingested_at discipline. The incremental watermark on this table is
       ONE clock shared across every unioned source: a source emitting rows
       behind it silently loses them; a source stamping ahead (now(), clock
       skew) drags the watermark past every OTHER source's upcoming rows.
       So in incremental mode _ingested_at is a hard per-source requirement
       -- fail at build time naming the offenders, never mask with a
       fallback. Table mode keeps the legacy occurred_at fallback: with no
       watermark there is nothing to corrupt. #}
    {% set ns = namespace(has_ingested_at=false) %}
    {% set relations_missing_ingested_at = [] %}
    {% if execute %}
        {% for rel in relations_to_union %}
            {% set rel_cols = adapter.get_columns_in_relation(rel) %}
            {% set rel_ns = namespace(has_col=false) %}
            {% for col in rel_cols %}
                {% if col.name | lower == '_ingested_at' %}
                    {% set rel_ns.has_col = true %}
                    {% set ns.has_ingested_at = true %}
                {% endif %}
            {% endfor %}
            {# Zero columns means the relation isn't built yet (fresh
               database, dbt compile, partial selection) -- unverifiable now,
               and execution-time rendering re-checks once upstreams exist.
               Only a BUILT relation lacking the column is an offense. #}
            {% if rel_cols | length > 0 and not rel_ns.has_col %}
                {% do relations_missing_ingested_at.append(rel | string) %}
            {% endif %}
        {% endfor %}
        {% if nexus.nexus_incremental_enabled() and relations_missing_ingested_at | length > 0 %}
            {{ exceptions.raise_compiler_error(
                "nexus incremental: every source feeding identity resolution must "
                ~ "expose a stable, non-null _ingested_at column (real ingestion/"
                ~ "load time -- never occurred_at, never now()). Missing from: "
                ~ relations_missing_ingested_at | join(", ")
                ~ ". Fix the source's entity_identifiers model, disable the "
                ~ "source, or turn off nexus.incremental.enabled. For static/"
                ~ "seed sources, stamp a data-vintage literal and bump it when "
                ~ "the data changes (re-offering rows is idempotent). See "
                ~ "docs/incremental-identity-resolution.md §4.7."
            ) }}
        {% endif %}
    {% endif %}

    {% if relations_to_union %}
        with unioned as (
            {{ dbt_utils.union_relations(
                relations=relations_to_union
            ) }}
        ),

        normalized as (
            -- Standardize identifier formats (lowercase emails, etc.)
            select
                entity_identifier_id,
                event_id,
                edge_id,
                entity_type,
                identifier_type,
                identifier_value,
                -- Normalize identifier values based on type
                case
                    when identifier_type = 'email' then lower(identifier_value)
                    when identifier_type = 'phone' then regexp_replace(identifier_value, '[^0-9]', '') -- Keep only digits
                    when identifier_type = 'domain' then lower(identifier_value)
                    else identifier_value
                end as normalized_value,
                role,
                source,
                occurred_at,
                {% if nexus.nexus_incremental_enabled() %}
                {# Hard edge: every relation was verified above to carry the
                   column, and nulls are NOT masked -- a null here is a data
                   bug surfaced by the packaged not-null test, not silently
                   rewritten into event time. #}
                _ingested_at
                {% elif ns.has_ingested_at %}
                coalesce(_ingested_at, occurred_at) as _ingested_at
                {% else %}
                occurred_at as _ingested_at
                {% endif %}
            from unioned
        )

        select
            entity_identifier_id,
            event_id,
            edge_id,
            entity_type,
            identifier_type,
            identifier_value,
            normalized_value,
            role,
            source,
            occurred_at,
            _ingested_at
        from normalized
        {% if is_incremental() %}
        -- Incremental mode: only rows ingested after the high-water mark.
        -- Watermark is on ingestion time, never occurred_at -- late-arriving
        -- events (old occurred_at, new _ingested_at) must still enter.
        where _ingested_at > coalesce(
            (select max(_ingested_at) from {{ this }}),
            cast('1970-01-01' as timestamp)
        )
        -- Batch-level dedup: warehouse merges reject duplicate unique_key
        -- values within one batch.
        qualify row_number() over (
            partition by entity_identifier_id
            order by _ingested_at desc
        ) = 1
        {% endif %}
    {% else %}
        {# Return empty result if no relations found #}
        select 
            cast(null as string) as entity_identifier_id,
            cast(null as string) as event_id,
            cast(null as string) as edge_id,
            cast(null as string) as entity_type,
            cast(null as string) as identifier_type,
            cast(null as string) as identifier_value,
            cast(null as string) as normalized_value,
            cast(null as string) as role,
            cast(null as string) as source,
            cast(null as timestamp) as occurred_at,
            cast(null as timestamp) as _ingested_at
        where 1=0
    {% endif %}
{% endmacro %}
