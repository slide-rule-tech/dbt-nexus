-- Entity identifiers for Segment identify events
-- Uses nexus.unpivot_identifiers to extract person identifiers
-- Follows nexus entity identifiers schema pattern

{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'entities'], 
    materialized='table'
) }}

with identifiers as (
{{ nexus.unpivot_identifiers(
    model_name='segment_events',
    columns=['segment_anonymous_id'] + var('nexus', {}).get('sources', {}).get('segment', {}).get('identifiers', []),
    event_id_field='event_id',
    edge_id_field='event_id',
    additional_columns=['occurred_at', "'segment' as source"],
        entity_type='person',
        role_column="'visitor'"
    ) }}
)

select * from identifiers
order by occurred_at desc
