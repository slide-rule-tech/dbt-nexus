-- Person identifiers for Segment identify events
-- Uses nexus.unpivot_identifiers to extract person identifiers
-- Follows nexus person identifiers schema pattern

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'persons'], 
    materialized='table'
) }}

{{ nexus.unpivot_identifiers(
    model_name='segment_identify_events',
    columns=['segment_anonymous_id'] + var('nexus', {}).get('segment', {}).get('identifiers', []),
    event_id_field='event_id',
    edge_id_field='event_id',
    additional_columns=['occurred_at', "'segment' as source"],
    entity_type='person',
    role_column="'visitor'"
) }}

order by occurred_at desc
