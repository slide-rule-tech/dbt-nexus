{%- macro union_segment_tracks() -%}
    {% if var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false) and var('segment_sources', []) | length > 0 %}
        {% set segment_tracks = [] %}
        {% set segment_sources = var("segment_sources") %}
        {% for segment_source in segment_sources %}
            {% for track in segment_source.tracks %}
                {% do segment_tracks.append(source(segment_source.name, track.name)) %}
            {% endfor %}
        {% endfor %}

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
        -- Segment is disabled or no segment sources configured, return empty result set
        select 
            null as id,
            null as timestamp,
            null as _dbt_source_relation
        where false
    {% endif %}
{%- endmacro -%}