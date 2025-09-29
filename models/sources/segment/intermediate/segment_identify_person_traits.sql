-- Person traits for Segment identify events
-- Uses nexus.unpivot_traits to extract person traits
-- Follows nexus person traits schema pattern

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'persons'], 
    materialized='table'
) }}

{{ nexus.unpivot_traits(
    model_name='segment_identify_events',
    columns=['segment_anonymous_id', 'user_id', 'email', 'first_name'],
    identifier_column='segment_anonymous_id',
    identifier_type='segment_anonymous_id',
    event_id_field='event_id',
    additional_columns=['occurred_at', "'segment' as source"],
    column_to_trait_name={
        'segment_anonymous_id': 'anonymous_id',
        'user_id': 'user_id',
        'email': 'email',
        'first_name': 'first_name'
    },
    entity_type='person'
) }}

order by occurred_at desc
