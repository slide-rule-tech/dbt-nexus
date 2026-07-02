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

    {# Detect whether any source relation carries _ingested_at. Sources that
       lack it fall back to occurred_at, so the ingestion watermark used by
       incremental mode degrades gracefully rather than failing to compile. #}
    {% set ns = namespace(has_ingested_at=false) %}
    {% if execute %}
        {% for rel in relations_to_union %}
            {% for col in adapter.get_columns_in_relation(rel) %}
                {% if col.name | lower == '_ingested_at' %}
                    {% set ns.has_ingested_at = true %}
                {% endif %}
            {% endfor %}
        {% endfor %}
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
                {% if ns.has_ingested_at %}
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
