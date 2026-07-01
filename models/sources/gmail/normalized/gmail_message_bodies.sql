{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('bodies', false),
    materialized='table',
    tags=['gmail', 'normalized', 'bodies']
) }}

-- Latest body per message_id_header. The collection is append-only, so re-pulling
-- a message lands a new row (same message_id_header); keep the newest by fetched_at.
-- Keyed by message_id_header to join straight onto gmail_messages / *_events.

WITH base AS (
    SELECT * FROM {{ ref('gmail_message_bodies_base') }}
)

SELECT
    message_id_header,
    gmail_account_email,
    gmail_account_message_id,
    body_plain,
    body_html,
    body_text_from_html,
    -- Convenience: the readable text, whichever form we have.
    COALESCE(body_plain, body_text_from_html) AS body_text,
    body_size_bytes,
    body_truncated_at_bytes,
    (body_truncated_at_bytes IS NOT NULL) AS body_truncated,
    fetched_at
FROM base
WHERE message_id_header IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY message_id_header
    ORDER BY fetched_at DESC, _queued_at DESC
) = 1
