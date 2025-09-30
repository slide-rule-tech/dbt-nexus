{%- macro union_segment_tracks() -%}
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
{%- endmacro -%}