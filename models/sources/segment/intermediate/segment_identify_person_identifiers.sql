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
    columns=['segment_anonymous_id', 'user_id', 'email'],
    event_id_field='event_id',
    edge_id_field='event_id',
    additional_columns=['occurred_at', "'segment' as source"],
    column_to_identifier_type={
      'segment_anonymous_id': 'segment_anonymous_id',
      'user_id': 'user_id',
      'email': 'email'
    },
    entity_type='person',
    role_column="'visitor'"
) }}

order by occurred_at desc
