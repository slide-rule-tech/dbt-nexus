{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized=nexus.nexus_incremental_materialization(),
    partition_by=nexus.nexus_bq_partition_by('_ingested_at', granularity='month'),
    cluster_by=nexus.nexus_cluster_by(['event_id']),
    unique_key='event_id',
    on_schema_change='append_new_columns',
    tags=['nexus', 'google_calendar', 'intermediate', 'events']
) }}

{{ nexus.nexus_incremental_upgrade_guard(['_ingested_at', 'event_id']) }}

-- Extract calendar events from normalized google_calendar_events
SELECT
    {{ nexus.create_nexus_id('event', ['event_id']) }} as event_id,
    instance_start as occurred_at,
    CASE 
        WHEN has_external_attendees THEN 'external_meeting'
        ELSE 'internal_meeting'
    END as event_name,
    COALESCE(summary, 'Calendar Event') as event_description,
    -- `event_significance` was a typo: nexus_events selects the column `significance`,
    -- so calendar rows had NULL significance downstream. Renamed to `significance`
    -- and bumped to 100 — calendar meetings are the highest-signal engagement.
    100 as significance,
    'calendar_event' as event_type,
    source,
    _ingested_at,
    event_id as calendar_event_key,
    calendar_id,
    ical_uid,
    calendar_event_id,
    instance_start,
    summary,
    description,
    location,
    status,
    start_time,
    end_time,
    is_all_day,
    is_recurring
FROM {{ ref('google_calendar_events_normalized') }}
WHERE start_time IS NOT NULL
{% if is_incremental() %}
  AND _ingested_at > {{ nexus.nexus_incremental_watermark_literal('_ingested_at') }}
{% endif %}
