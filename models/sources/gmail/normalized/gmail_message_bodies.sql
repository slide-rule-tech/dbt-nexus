{{ config(
    enabled=var('nexus', {}).get('sources', {}).get('gmail', {}).get('bodies', false),
    materialized='table',
    tags=['gmail', 'normalized', 'bodies']
) }}

-- Normalized layer: extract the body fields from the landed row's _raw_record
-- (cross-adapter via nexus.json_path) and dedup latest-per-message_id_header.
-- Keyed by message_id_header to join straight onto gmail_messages / *_events.
--
-- Two producers land the same _raw_record shape (message_id_header,
-- gmail_account_email, gmail_account_message_id, body_plain, body_html,
-- body_text_from_html, body_size_bytes, body_truncated_at_bytes, fetched_at)
-- in two different envelopes:
--   * the gmail_message_body BBP enricher, pulled on demand into the lean BBP
--     envelope (`_queued_at`, `_row_id`, ...);
--   * the Workspace Gmail ingestion's `gmailBodies` option, synced nightly
--     into the standard ingestion envelope (`_ingested_at`, `_sync_id`, ...).
-- Point `tables.message_bodies.identifier` at whichever table the project
-- uses. Both collections are append-only, so re-pulling a message lands a new
-- row (same message_id_header) -- keep the newest by fetched_at, breaking ties
-- on whichever landing clock the envelope carries.

{%- set bodies_relation = source('gmail', 'message_bodies') -%}
{%- set landed_cols = [] -%}
{%- if execute -%}
  {%- set landed_cols = adapter.get_columns_in_relation(bodies_relation)
        | map(attribute='name') | map('lower') | list -%}
{%- endif -%}
{%- if '_queued_at' in landed_cols -%}
  {%- set landed_at_column = '_queued_at' -%}
{%- elif '_ingested_at' in landed_cols -%}
  {%- set landed_at_column = '_ingested_at' -%}
{%- else -%}
  {%- set landed_at_column = none -%}
{%- endif %}

with base as (
    select * from {{ ref('gmail_message_bodies_base') }}
),

extracted as (
    select
        {{ nexus.json_path('_raw_record', 'message_id_header', 'string') }} as message_id_header,
        {{ nexus.json_path('_raw_record', 'gmail_account_email', 'string') }} as gmail_account_email,
        {{ nexus.json_path('_raw_record', 'gmail_account_message_id', 'string') }} as gmail_account_message_id,
        {{ nexus.json_path('_raw_record', 'body_plain', 'string') }} as body_plain,
        {{ nexus.json_path('_raw_record', 'body_html', 'string') }} as body_html,
        {{ nexus.json_path('_raw_record', 'body_text_from_html', 'string') }} as body_text_from_html,
        {{ nexus.json_path('_raw_record', 'body_size_bytes', 'bigint') }} as body_size_bytes,
        {{ nexus.json_path('_raw_record', 'body_truncated_at_bytes', 'bigint') }} as body_truncated_at_bytes,
        {{ nexus.json_path('_raw_record', 'fetched_at', 'timestamp') }} as fetched_at,
        {% if landed_at_column %}{{ landed_at_column }}{% else %}cast(null as {{ dbt.type_timestamp() }}){% endif %} as landed_at
    from base
)

select
    message_id_header,
    gmail_account_email,
    gmail_account_message_id,
    body_plain,
    body_html,
    body_text_from_html,
    -- Convenience: the readable text, whichever form we have.
    coalesce(body_plain, body_text_from_html) as body_text,
    body_size_bytes,
    body_truncated_at_bytes,
    (body_truncated_at_bytes is not null) as body_truncated,
    fetched_at
from extracted
where message_id_header is not null
qualify row_number() over (
    partition by message_id_header
    order by fetched_at desc, landed_at desc
) = 1
