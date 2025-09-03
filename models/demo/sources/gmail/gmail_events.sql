
WITH source_events AS (
    SELECT
        event_id,
        event_name,
        occurred_at,
        event_description,
        null as event_value,
        null as value_unit,
        CAST(NULL AS STRING) as event_significance,
        'email' as event_type,
        source,
        'gmail_messages' as source_table,
        synced_at,
        CAST(NULL AS BOOL) as realtime_processed
    FROM {{ ref('gmail_messages_base') }}
)

SELECT * FROM source_events
ORDER BY occurred_at DESC 