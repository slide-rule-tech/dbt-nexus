{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false)
) }}

{{ nexus.union_segment_sources('identifies') }}