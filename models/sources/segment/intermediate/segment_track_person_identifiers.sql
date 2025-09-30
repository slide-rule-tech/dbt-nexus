-- Person identifiers for Segment track events
-- Uses nexus.unpivot_identifiers to extract person identifiers
-- Follows nexus person identifiers schema pattern

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'persons'], 
    materialized='table'
) }}

{{ nexus.unpivot_identifiers(
    model_name='segment_track_events',
    columns=['segment_anonymous_id'],
    event_id_field='event_id',
    edge_id_field='event_id',
    additional_columns=['occurred_at', "'segment' as source"],
    role_column="'visitor'",
    entity_type='person'
) }}
order by occurred_at desc
