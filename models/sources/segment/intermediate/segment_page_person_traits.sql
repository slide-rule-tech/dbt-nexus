-- Person traits for Segment identify events
-- Uses nexus.unpivot_traits to extract person traits
-- Follows nexus person traits schema pattern

{{ config(
    enabled=var('nexus', {}).get('segment', {}).get('enabled', false),
    tags=['identity-resolution', 'persons'], 
    materialized='table'
) }}

{{ nexus.unpivot_traits(
    model_name='segment_page_events',
    columns=['segment_anonymous_id'],
    identifier_column='segment_anonymous_id',
    identifier_type='segment_anonymous_id',
    event_id_field='event_id',
    additional_columns=['occurred_at', "'segment' as source"],

    entity_type='person'
) }}

order by occurred_at desc
