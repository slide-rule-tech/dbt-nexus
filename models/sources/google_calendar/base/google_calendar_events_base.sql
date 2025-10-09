
{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('google_calendar', {}).get('enabled', false),
    materialized='table',
    tags=['event-processing', 'realtime']
) }}

WITH source_data AS (
    SELECT
        JSON_EXTRACT_SCALAR(record, '$.id') as event_id,
        *
    FROM {{ source('google_calendar', 'calendar_events') }}
),

event_filter AS (
    SELECT
        *
    FROM source_data
),

extracted AS (
    SELECT
        {{ create_nexus_id('event', ['event_id']) }} as nexus_event_id,
        
        -- Event details
        event_id as calendar_event_id,
        JSON_EXTRACT_SCALAR(record, '$.summary') as summary,
        JSON_EXTRACT_SCALAR(record, '$.description') as description,
        JSON_EXTRACT_SCALAR(record, '$.location') as location,
        JSON_EXTRACT_SCALAR(record, '$.status') as status,
        
        -- Parse start and end times
        CAST(PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', 
            COALESCE(
                JSON_EXTRACT_SCALAR(record, '$.start.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(record, '$.start.date'), 'T00:00:00Z')
            )
        ) AS TIMESTAMP) as start_time,
        
        CAST(PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', 
            COALESCE(
                JSON_EXTRACT_SCALAR(record, '$.end.dateTime'),
                CONCAT(JSON_EXTRACT_SCALAR(record, '$.end.date'), 'T23:59:59Z')
            )
        ) AS TIMESTAMP) as end_time,
        
        -- Check if it's all day event
        CASE 
            WHEN JSON_EXTRACT_SCALAR(record, '$.start.date') IS NOT NULL THEN true
            ELSE false
        END as is_all_day,
        
        -- Organizer info
        STRUCT(
            JSON_EXTRACT_SCALAR(record, '$.organizer.email') as email,
            JSON_EXTRACT_SCALAR(record, '$.organizer.displayName') as name,
            REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(record, '$.organizer.email'), r'@(.+)') as domain,
            REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(record, '$.organizer.email'), r'@(.+)') IN (
                {%- for domain in var('internal_domains') -%}
                '{{ domain }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            ) as is_internal,
            CAST(JSON_EXTRACT_SCALAR(record, '$.organizer.self') AS BOOL) as is_self
        ) as organizer,
        
        -- Creator info  
        STRUCT(
            JSON_EXTRACT_SCALAR(record, '$.creator.email') as email,
            JSON_EXTRACT_SCALAR(record, '$.creator.displayName') as name,
            REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(record, '$.creator.email'), r'@(.+)') as domain,
            REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(record, '$.creator.email'), r'@(.+)') IN (
                {%- for domain in var('internal_domains') -%}
                '{{ domain }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            ) as is_internal
        ) as creator,
        
        -- Parse attendees array
        ARRAY(
            SELECT AS STRUCT
                JSON_EXTRACT_SCALAR(attendee, '$.email') as email,
                JSON_EXTRACT_SCALAR(attendee, '$.displayName') as name,
                REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(attendee, '$.email'), r'@(.+)') as domain,
                REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(attendee, '$.email'), r'@(.+)') IN (
                    {%- for domain in var('internal_domains') -%}
                    '{{ domain }}'
                    {%- if not loop.last -%},{%- endif -%}
                    {%- endfor -%}
                ) as is_internal,
                JSON_EXTRACT_SCALAR(attendee, '$.responseStatus') as response_status,
                CAST(JSON_EXTRACT_SCALAR(attendee, '$.optional') AS BOOL) as is_optional,
                CAST(JSON_EXTRACT_SCALAR(attendee, '$.organizer') AS BOOL) as is_organizer,
                CAST(JSON_EXTRACT_SCALAR(attendee, '$.self') AS BOOL) as is_self
            FROM UNNEST(JSON_EXTRACT_ARRAY(record, '$.attendees')) as attendee
            WHERE JSON_EXTRACT_SCALAR(attendee, '$.email') IS NOT NULL
            AND JSON_EXTRACT_SCALAR(attendee, '$.email') != ''
        ) as attendees,
        
        -- Determine if meeting has external attendees
        (
            SELECT COUNT(*) > 0
            FROM UNNEST(JSON_EXTRACT_ARRAY(record, '$.attendees')) as attendee
            WHERE REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(attendee, '$.email'), r'@(.+)') NOT IN (
                {%- for domain in var('internal_domains') -%}
                '{{ domain }}'
                {%- if not loop.last -%},{%- endif -%}
                {%- endfor -%}
            )
            AND JSON_EXTRACT_SCALAR(attendee, '$.email') IS NOT NULL
        ) OR REGEXP_EXTRACT(JSON_EXTRACT_SCALAR(record, '$.organizer.email'), r'@(.+)') NOT IN (
            {%- for domain in var('internal_domains') -%}
            '{{ domain }}'
            {%- if not loop.last -%},{%- endif -%}
            {%- endfor -%}
        ) as has_external_attendees,
        
        -- Keep the original record for reference
        record as raw_record,
        synced_at
    FROM event_filter
),

with_latest_events AS (
    {{ nexus.get_first_or_last_row(
        source='extracted',
        partition_by='calendar_event_id',
        order_by='start_time',
        column_label='is_latest',
        get='last'
    ) }}
),

deduped_events AS (
    SELECT *
    FROM with_latest_events
    WHERE is_latest
),

final AS (
    SELECT 
        *,
        'google_calendar' as source,
        CASE 
            WHEN has_external_attendees THEN 'external_meeting'
            ELSE 'internal_meeting'
        END as event_name,
        COALESCE(summary, 'Calendar Event') as event_description
    FROM deduped_events
    WHERE start_time < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 14 DAY)
)

SELECT * FROM final
ORDER BY start_time DESC
