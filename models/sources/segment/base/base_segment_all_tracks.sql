{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false)
) }}

{{ nexus.union_segment_sources('tracks') }}