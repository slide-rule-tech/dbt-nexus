{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false)
) }}

{# Check if any segment sources define selected tracks #}
{% set sources_with_tracks = [] %}
{% for segment_source in var('segment_sources', []) %}
    {% if segment_source.get('tracks', none) is not none %}
        {% do sources_with_tracks.append(segment_source.name) %}
    {% endif %}
{% endfor %}
{% set has_selected_tracks = sources_with_tracks | length > 0 %}

{% if has_selected_tracks %}
    {# Filter all_tracks using selected_tracks #}
    {{ nexus.join_and_rename_or_drop(
        rename='drop',
        ref1=ref('base_segment_all_tracks'),
        ref2=ref('base_segment_selected_tracks'),
        id1='id',
        id2='id',
        prefix2='selected_'
    ) }}
{% else %}
    {# No selected tracks configured, use all tracks #}
    select * from {{ ref('base_segment_all_tracks') }}
{% endif %}