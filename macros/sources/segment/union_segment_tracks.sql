{%- macro union_segment_tracks() -%}
    {% if var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false) and var('segment_sources', []) | length > 0 %}
        {% set segment_tracks = [] %}
        {% set segment_sources = var("segment_sources") %}
        {% for segment_source in segment_sources %}
            {% if segment_source.get('tracks', none) is not none %}
                {% for track in segment_source.tracks %}
                    {% do segment_tracks.append(source(segment_source.name, track.name)) %}
                {% endfor %}
            {% endif %}
        {% endfor %}

        {% if segment_tracks | length > 0 %}
        with unioned as (
            {{ dbt_utils.union_relations(
                relations=segment_tracks,
                source_column_name='_dbt_source_relation'
            ) }}
        )

        select 
            *
        from  unioned
        {% else %}
        -- No selected tracks configured on any segment source
        select 
            cast(null as string) as id,
            cast(null as timestamp) as timestamp,
            cast(null as string) as _dbt_source_relation
        limit 0
        {% endif %}
    {% else %}
        -- Segment is disabled or no segment sources configured, return empty result set
        select 
            cast(null as string) as id,
            cast(null as timestamp) as timestamp,
            cast(null as string) as _dbt_source_relation
        limit 0
    {% endif %}
{%- endmacro -%}