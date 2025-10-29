# Updating Gmail and Google Calendar dbt Models for New Ingestion Schema

This document outlines the changes required to update the Gmail and Google
Calendar dbt models to work with the new Convex ingestion system schema.

## Overview

The new ingestion system uses a standardized table schema
(`STANDARD_TABLE_SCHEMA`) that differs from the previous Nango sync structure.
Additionally, Gmail messages have been restructured to remove large payload
fields and include extracted fields.

## Schema Changes: STANDARD_TABLE_SCHEMA

### Old Schema (Nango Sync)

```sql
-- Old table structure
record      JSON      -- Raw JSON record
synced_at   TIMESTAMP -- Sync timestamp
```

### New Schema (Convex Ingestion)

```sql
-- New standardized table structure
_ingested_at      TIMESTAMP  NOT NULL  -- When record was ingested
_connection_id    STRING     NOT NULL  -- Nango connection ID
_stream_id        STRING     NOT NULL  -- Stream identifier (e.g., calendar ID, 'default')
_raw_record       JSON       NOT NULL  -- Raw JSON record (renamed from 'record')
_sync_timestamp   TIMESTAMP   NULLABLE  -- For timestamp-based cursors
_sync_token       STRING      NULLABLE  -- For token-based cursors (history IDs, sync tokens)
```

### Required Updates in Base Models

Both `gmail_messages_base.sql` and `google_calendar_events_base.sql` need to:

1. **Change source column references:**

   - `record` → `_raw_record`
   - `synced_at` → `_ingested_at`

2. **Update JSON extraction paths:**

   - `JSON_EXTRACT_SCALAR(record, '$.field')` →
     `JSON_EXTRACT_SCALAR(_raw_record, '$.field')`
   - Same for `JSON_EXTRACT_ARRAY(record, '$.field')` →
     `JSON_EXTRACT_ARRAY(_raw_record, '$.field')`

3. **Use new timestamp field:**
   - Replace `synced_at` references with `_ingested_at`

## Gmail-Specific Changes

### Gmail Record Structure Changes

#### Old Structure (Nango)

```json
{
  "id": "message_id",
  "sender": "sender@example.com",
  "recipients": "recipient1@example.com,recipient2@example.com",
  "date": "2023-01-01T12:00:00Z",
  "subject": "Email Subject",
  "body": "Email body content",
  "threadId": "thread_id"
}
```

#### New Structure (Convex Ingestion)

```json
{
  "id": "message_id",
  "threadId": "thread_id",
  "internalDate": "1234567890000",
  "historyId": "history_id",
  "labelIds": ["INBOX", "SENT"],
  "sizeEstimate": 12345,
  "snippet": "Email preview text",
  "body_text": "Extracted plain text body",
  "attachments": [
    {
      "filename": "file.pdf",
      "mimeType": "application/pdf",
      "size": 12345,
      "attachmentId": "attachment_id"
    }
  ],
  "headers": [
    { "name": "Message-ID", "value": "<message-id@example.com>" },
    { "name": "From", "value": "Sender Name <sender@example.com>" },
    { "name": "To", "value": "recipient1@example.com, recipient2@example.com" },
    { "name": "Subject", "value": "Email Subject" },
    { "name": "Date", "value": "Mon, 1 Jan 2023 12:00:00 -0000" }
  ],
  "_updated_at": "2023-01-01T12:00:00.000Z",
  "_sync_timestamp": "2023-01-01T12:00:00.000Z"
}
```

**Key Changes:**

- ❌ Removed: `sender`, `recipients`, `date`, `subject`, `body`, `payload`,
  `raw`
- ✅ Added: `body_text` (pre-extracted), `attachments` (metadata), `headers`
  (array)
- ✅ Changed: Direct fields → Extracted from `headers` array
- ✅ Available: `internalDate` (Unix timestamp in milliseconds)

### Required Updates in `gmail_messages_base.sql`

1. **Update source query:**

   ```sql
   -- OLD
   FROM {{ nexus_source('gmail', 'messages') }}

   -- NEW (no change needed if nexus_source handles it, but verify table name)
   FROM {{ nexus_source('gmail', 'gmail_messages') }}  -- Verify actual table name
   ```

2. **Update column references in source_data CTE:**

   ```sql
   -- OLD
   WITH source_data AS (
       SELECT
           JSON_EXTRACT_SCALAR(record, '$.id') as message_id,
           *
       FROM {{ nexus_source('gmail', 'messages') }}
   )

   -- NEW
   WITH source_data AS (
       SELECT
           JSON_EXTRACT_SCALAR(_raw_record, '$.id') as message_id,
           _ingested_at,
           _connection_id,
           _stream_id,
           _sync_timestamp,
           _sync_token,
           _raw_record as record  -- Keep as 'record' for backward compatibility in rest of query
       FROM {{ nexus_source('gmail', 'gmail_messages') }}
   )
   ```

3. **Extract fields from headers array:**

   ```sql
   -- OLD
   JSON_EXTRACT_SCALAR(record, '$.sender') as sender,
   JSON_EXTRACT_SCALAR(record, '$.recipients') as recipients,
   JSON_EXTRACT_SCALAR(record, '$.subject') as subject,
   CAST(PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S%Ez', JSON_EXTRACT_SCALAR(record, '$.date')) AS TIMESTAMP) as occurred_at,
   JSON_EXTRACT_SCALAR(record, '$.body') as body,

   -- NEW
   -- Extract Message-ID from headers (for cross-account matching)
   (SELECT value FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
    WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'message-id'
    LIMIT 1) as message_id_header,

   -- Extract From header
   (SELECT value FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
    WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'from'
    LIMIT 1) as sender_raw,

   -- Extract To header (may need to concatenate with Cc, Bcc)
   CONCAT(
     COALESCE((SELECT value FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
                WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'to'
                LIMIT 1), ''),
     CASE WHEN (SELECT value FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
                WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'cc'
                LIMIT 1) IS NOT NULL
          THEN ', ' || (SELECT value FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
                         WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'cc'
                         LIMIT 1)
          ELSE ''
     END
   ) as recipients_raw,

   -- Extract Subject header
   (SELECT value FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
    WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'subject'
    LIMIT 1) as subject,

   -- Use internalDate (Unix timestamp in milliseconds) for occurred_at
   TIMESTAMP_MILLIS(CAST(JSON_EXTRACT_SCALAR(_raw_record, '$.internalDate') AS INT64)) as occurred_at,

   -- Use pre-extracted body_text
   JSON_EXTRACT_SCALAR(_raw_record, '$.body_text') as body,

   -- Use attachments array
   JSON_EXTRACT_ARRAY(_raw_record, '$.attachments') as attachments_array,
   ```

4. **Update synced_at references:**

   ```sql
   -- OLD
   synced_at

   -- NEW
   _ingested_at as synced_at  -- Keep as synced_at for backward compatibility
   ```

5. **Handle thread_id:**

   ```sql
   -- OLD
   JSON_EXTRACT_SCALAR(record, '$.threadId') as thread_id,

   -- NEW (no change, still available)
   JSON_EXTRACT_SCALAR(_raw_record, '$.threadId') as thread_id,
   ```

## Google Calendar-Specific Changes

### Google Calendar Record Structure

The Google Calendar structure is likely unchanged, but we need to update column
references:

#### Expected New Structure

```json
{
  "id": "event_id",
  "summary": "Event Title",
  "description": "Event Description",
  "start": {"dateTime": "...", "date": "..."},
  "end": {"dateTime": "...", "date": "..."},
  "organizer": {...},
  "creator": {...},
  "attendees": [...],
  ...
}
```

### Required Updates in `google_calendar_events_base.sql`

1. **Update source query:**

   ```sql
   -- OLD
   FROM {{ source('google_calendar', 'calendar_events') }}

   -- NEW
   FROM {{ source('google_calendar', 'google_calendar_events') }}  -- Verify actual table name
   ```

2. **Update column references in source_data CTE:**

   ```sql
   -- OLD
   WITH source_data AS (
       SELECT
           JSON_EXTRACT_SCALAR(record, '$.id') as event_id,
           *
       FROM {{ source('google_calendar', 'calendar_events') }}
   )

   -- NEW
   WITH source_data AS (
       SELECT
           JSON_EXTRACT_SCALAR(_raw_record, '$.id') as event_id,
           _ingested_at,
           _connection_id,
           _stream_id,
           _sync_timestamp,
           _sync_token,
           _raw_record as record  -- Keep as 'record' for backward compatibility
       FROM {{ source('google_calendar', 'google_calendar_events') }}
   )
   ```

3. **Update all JSON_EXTRACT references:**

   ```sql
   -- OLD
   JSON_EXTRACT_SCALAR(record, '$.field')

   -- NEW
   JSON_EXTRACT_SCALAR(_raw_record, '$.field')
   ```

4. **Update synced_at references:**

   ```sql
   -- OLD
   synced_at

   -- NEW
   _ingested_at as synced_at  -- Keep as synced_at for backward compatibility
   ```

5. **Consider using \_sync_timestamp for event timing:**

   ```sql
   -- If _sync_timestamp is more accurate than parsing from event JSON
   COALESCE(
     _sync_timestamp,
     CAST(PARSE_TIMESTAMP(...) AS TIMESTAMP)
   ) as start_time
   ```

## Normalized Model Updates

### `gmail_messages.sql` Updates

Update the normalized model to include new fields:

```sql
-- Add new fields if needed
SELECT
    event_id,
    occurred_at,
    message_id,
    thread_id,
    sender_raw,
    recipients_raw,
    subject,
    body,
    sender,
    recipients,
    -- Add new Gmail fields
    attachments_array,  -- If needed
    message_id_header,  -- For cross-account matching
    --
    _raw_record as raw_record,  -- Use _raw_record now
    synced_at,  -- Maps to _ingested_at
    source
FROM {{ ref('gmail_messages_base') }}
QUALIFY row_number() over (partition by message_id order by occurred_at desc) = 1
```

### `google_calendar_events_normalized.sql` Updates

Minimal changes needed, just ensure column references are updated:

```sql
SELECT
    nexus_event_id,
    calendar_event_id,
    summary,
    description,
    location,
    status,
    start_time,
    end_time,
    is_all_day,
    organizer,
    creator,
    attendees,
    has_external_attendees,
    source,
    event_name,
    event_description,
    synced_at  -- Now maps to _ingested_at
FROM {{ ref('google_calendar_events_base') }}
```

## Source Definition Updates

### `gmail.yml` Updates

Update source definition to reference new table:

```yaml
sources:
  - name:
      "{{ var('nexus', {}).get('gmail', {}).get('location', {}).get('schema',
      'gmail') }}"
    tables:
      - name: "{{ var('nexus', {}).get('gmail', {}).get('location',
          {}).get('table', 'gmail_messages') }}" # Updated default
        columns:
          - name: _ingested_at
            description: "Timestamp when record was ingested"
          - name: _connection_id
            description: "Nango connection ID"
          - name: _stream_id
            description: "Stream identifier"
          - name: _raw_record
            description: "Raw JSON record"
          - name: _sync_timestamp
            description: "Timestamp-based cursor"
          - name: _sync_token
            description: "Token-based cursor"
```

### `google_calendar.yml` Updates

```yaml
sources:
  - name: google_calendar
    description: "Google Calendar events synced via Convex ingestion"
    tables:
      - name: google_calendar_events # Updated table name
        description: "Raw Google Calendar events from Convex sync"
        columns:
          - name: _ingested_at
            description: "Timestamp when record was ingested"
            data_type: timestamp
          - name: _connection_id
            description: "Nango connection ID"
            data_type: string
          - name: _stream_id
            description: "Stream identifier (calendar ID)"
            data_type: string
          - name: _raw_record
            description: "JSON record from Google Calendar API"
            data_type: json
          - name: _sync_timestamp
            description: "Timestamp-based cursor"
            data_type: timestamp
          - name: _sync_token
            description: "Token-based cursor (sync token)"
            data_type: string
```

## Summary Checklist

### For Both Sources

- [ ] Update source table references (`record` → `_raw_record`, `synced_at` →
      `_ingested_at`)
- [ ] Update all `JSON_EXTRACT_SCALAR(record, ...)` →
      `JSON_EXTRACT_SCALAR(_raw_record, ...)`
- [ ] Update all `JSON_EXTRACT_ARRAY(record, ...)` →
      `JSON_EXTRACT_ARRAY(_raw_record, ...)`
- [ ] Add `_connection_id`, `_stream_id`, `_sync_timestamp`, `_sync_token` to
      source_data CTE
- [ ] Update source definitions in `.yml` files
- [ ] Verify table names match actual BigQuery tables

### For Gmail Specifically

- [ ] Extract `sender` from `headers` array (look for `From` header)
- [ ] Extract `recipients` from `headers` array (concatenate `To`, `Cc`, `Bcc`
      if needed)
- [ ] Extract `subject` from `headers` array (`Subject` header)
- [ ] Use `body_text` instead of parsing from `body` or `payload`
- [ ] Use `TIMESTAMP_MILLIS()` to convert `internalDate` to timestamp
- [ ] Extract `Message-ID` from headers for cross-account matching
- [ ] Handle `attachments` array if needed in downstream models

### For Google Calendar Specifically

- [ ] Verify JSON structure is unchanged (likely same as before)
- [ ] Consider using `_sync_timestamp` if more accurate than parsing event times

## Testing

After making updates:

1. **Compile models:**

   ```bash
   dbt compile --models gmail_messages_base google_calendar_events_base
   ```

2. **Check for errors:**

   ```bash
   dbt parse
   ```

3. **Test queries:**

   ```sql
   -- Verify new schema columns exist
   SELECT _ingested_at, _connection_id, _stream_id, _raw_record
   FROM {{ source('gmail', 'gmail_messages') }}
   LIMIT 1;

   -- Verify Gmail header extraction works
   SELECT
     message_id,
     sender_raw,
     subject,
     occurred_at
   FROM {{ ref('gmail_messages_base') }}
   LIMIT 5;
   ```

4. **Run models:**

   ```bash
   dbt run --models gmail_messages_base google_calendar_events_base
   ```
