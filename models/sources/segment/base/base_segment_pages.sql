{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false)
) }}

{{ nexus.union_segment_sources('pages', column_override={"context_campaign_term": "string"}) }}
