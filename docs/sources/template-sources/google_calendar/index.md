---
title: Google Calendar Template Source
tags: [template-sources, google-calendar, calendar, meetings, configuration]
summary:
  Ready-to-use Google Calendar integration for meeting events, attendee
  tracking, and organization relationships
---

# Google Calendar Template Source

The **Google Calendar Template Source** provides instant integration with Google
Calendar data through the Nango ETL pipeline. It processes calendar events into
meeting events, extracts entity identifiers for people and groups, and creates
relationship declarations - all through simple configuration.

## Overview

The Google Calendar template source transforms raw calendar data into the nexus
framework using the v0.3.0 entity-centric architecture:

- **📅 Meeting Events**: Each calendar event becomes an `external_meeting` or
  `internal_meeting`
- **👥 Attendee Entities**: Extracts organizers, creators, and attendees as
  person entities
- **🏢 Organization Entities**: Creates groups from attendee email domains
- **🔗 Relationships**: Links people to their organizations via email domains
  (membership type)
- **🏷️ Entity Traits**: Captures meeting participant names and emails for all
  entities
- **🔄 Cross-Account Deduplication**: Uses `iCalUID` to deduplicate events
  across multiple calendars and accounts
- **📆 Recurring Event Support**: Automatically detects and handles recurring
  events using `instanceStart` timestamps

## Quick Start

### 1. Enable the Template Source

```yaml
# dbt_project.yml
vars:
  nexus:
    google_calendar:
      enabled: true
```

### 2. Run the Models

```bash
dbt run --select package:nexus
```

### 3. Explore Your Data

```sql
-- View recent calendar events
SELECT * FROM {{ ref('nexus_events') }}
WHERE source = 'google_calendar'
ORDER BY occurred_at DESC
LIMIT 10;

-- Find external meetings with attendee details
SELECT
    ev.event_description as meeting_title,
    ev.occurred_at,
    ev.is_recurring,
    COUNT(DISTINCT CASE WHEN ei.entity_type = 'person' THEN ei.identifier_value END) as person_count,
    COUNT(DISTINCT CASE WHEN ei.role = 'organizer' THEN ei.identifier_value END) as organizer_count,
    COUNT(DISTINCT CASE WHEN ei.role = 'attendee' THEN ei.identifier_value END) as attendee_count,
    ARRAY_AGG(DISTINCT e.email ORDER BY e.email) as attendee_emails
FROM {{ ref('nexus_events') }} ev
JOIN {{ ref('nexus_entity_identifiers') }} ei ON ev.event_id = ei.event_id
LEFT JOIN {{ ref('nexus_entities') }} e
    ON ei.identifier_value = e.email
    AND e.entity_type = 'person'
WHERE ev.source = 'google_calendar'
  AND ev.event_name = 'external_meeting'
GROUP BY ev.event_id, ev.event_description, ev.occurred_at, ev.is_recurring
ORDER BY ev.occurred_at DESC;
```

## Configuration

### Basic Configuration

```yaml
# dbt_project.yml
vars:
  nexus:
    google_calendar:
      enabled: true
      # Uses defaults: schema=google_calendar, table=google_calendar_events
```

### Custom Source Location

```yaml
vars:
  nexus:
    google_calendar:
      enabled: true
      location:
        schema: my_calendar_data
        table: google_calendar_events
```

### Required Global Variables

```yaml
vars:
  # Required: Define internal email domains for meeting classification
  internal_domains:
    - "yourcompany.com"
    - "subsidiary.com"

  # Optional: Test email addresses
  test_emails:
    - "test@yourcompany.com"
```

## Data Requirements

### Source Table Schema

Your Google Calendar source table must use the **STANDARD_TABLE_SCHEMA**
structure:

```sql
CREATE TABLE `project.schema.table` (
  _raw_record JSON NOT NULL,           -- Google Calendar event as JSON
  _ingested_at TIMESTAMP NOT NULL,      -- When the record was ingested
  _connection_id STRING NOT NULL,       -- Nango connection ID
  _stream_id STRING NOT NULL,           -- Stream identifier (calendar ID)
  _sync_timestamp TIMESTAMP,           -- Timestamp-based cursor for incremental sync
  _sync_token STRING                    -- Token-based cursor (sync token)
);
```

### Google Calendar Event JSON Structure

The `_raw_record` column should contain Google Calendar API event format:

```json
{
  "id": "event_id_123",
  "iCalUID": "ical_uid_abc123@google.com",
  "summary": "Team Meeting",
  "description": "Weekly team sync",
  "location": "Conference Room A",
  "status": "confirmed",
  "start": {
    "dateTime": "2024-01-15T10:00:00-08:00"
  },
  "end": {
    "dateTime": "2024-01-15T11:00:00-08:00"
  },
  "originalStartTime": {
    "dateTime": "2024-01-15T10:00:00-08:00"
  },
  "recurringEventId": "event_id_456",
  "organizer": {
    "email": "organizer@company.com",
    "displayName": "Meeting Organizer",
    "self": true
  },
  "creator": {
    "email": "creator@company.com",
    "displayName": "Event Creator"
  },
  "attendees": [
    {
      "email": "attendee1@company.com",
      "displayName": "Internal Attendee",
      "responseStatus": "accepted",
      "optional": false,
      "organizer": false,
      "self": false
    },
    {
      "email": "external@client.com",
      "displayName": "External Attendee",
      "responseStatus": "accepted"
    }
  ],
  "recurrence": ["RRULE:FREQ=WEEKLY;BYDAY=MO"]
}
```

**Key Fields:**

- `iCalUID`: Universal identifier for cross-account deduplication (required)
- `id`: Calendar-specific event ID (unique within a single calendar)
- `originalStartTime`: Used for recurring event instances
- `recurringEventId`: Indicates this is an instance of a recurring event
- `recurrence`: Array of RRULE strings for recurring events

## Generated Models

Google Calendar uses the **four-layer source architecture** with split
normalized models for optimal performance:

### Layer 1: Base - `google_calendar_events_base.sql`

Simple passthrough with zero transformation overhead:

**Key Features:**

- Direct `SELECT *` from source table
- No JSON parsing or transformations
- Minimal overhead for maximum performance

### Layer 2: Normalized - Split Structure

#### `google_calendar_events_normalized.sql` - Event-Level Data

Clean, deduplicated calendar events.

**Key Features:**

- **Cross-Account Deduplication**: Uses `iCalUID` as primary identifier
- **Recurring Event Support**:
  - Single events: keyed by `iCalUID`
  - Recurring instances: keyed by `iCalUID + instanceStart`
- **Instance Start Detection**: Priority order:
  1. `originalStartTime.dateTime` (for recurring instances)
  2. `start.dateTime` (for scheduled events)
  3. `start.date` (for all-day events)
- **Event Classification**: Detects external vs internal meetings
- **Recurring Flag**: `is_recurring` indicates if event is part of a series

**Contains:**

```sql
event_id               -- Composite key (iCalUID or iCalUID|instanceStart)
ical_uid               -- Universal calendar identifier
calendar_event_id      -- Calendar-specific ID (from $.id)
instance_start         -- Instance timestamp for recurring events
summary                -- Meeting title
description            -- Meeting description
location               -- Meeting location
status                 -- Event status
start_time             -- Parsed start timestamp
end_time               -- Parsed end timestamp
is_all_day             -- Boolean flag
is_recurring           -- Boolean flag
has_external_attendees -- Boolean flag
_ingested_at           -- Ingestion timestamp
raw_record             -- Full JSON record
_connection_id         -- Nango connection ID
_stream_id             -- Calendar ID
_sync_timestamp        -- Sync timestamp
_sync_token            -- Sync token
source                 -- "google_calendar"
```

**Deduplication Logic:**

- Single events:
  `QUALIFY row_number() OVER (PARTITION BY ical_uid ORDER BY _ingested_at DESC) = 1`
- Recurring events:
  `QUALIFY row_number() OVER (PARTITION BY (ical_uid, instance_start) ORDER BY _ingested_at DESC) = 1`

#### `google_calendar_event_participants.sql` - Participant-Level Data

One row per participant per event, normalized and validated.

**Key Features:**

- Extracts organizer, creator, and all attendees
- Uses Gmail email parsing macros for consistency
- Normalizes email addresses using `validate_and_normalize_email()`
- Extracts domains for group entity creation
- Preserves attendee metadata (response status, optional flags, etc.)

**Contains:**

```sql
event_id               -- Composite key matching events table
ical_uid               -- Universal calendar identifier
calendar_event_id      -- Calendar-specific ID
instance_start         -- Instance timestamp
participant_raw        -- Raw email from JSON
name                   -- Participant name
email                  -- Normalized email address
domain                 -- Extracted domain
role                   -- "organizer", "creator", or "attendee"
start_time             -- Event start time
_ingested_at           -- Ingestion timestamp
display_name           -- Display name from calendar
response_status        -- Accepted/declined/etc (attendees only)
is_optional            -- Optional flag (attendees only)
is_organizer           -- Is organizer flag (attendees only)
is_self                -- Is self flag (organizer/attendees)
```

**Role Types:**

- `organizer`: Person who organized the event
- `creator`: Person who created the event
- `attendee`: Person attending the event

### Layer 3: Intermediate - 6 Models

Separate person/group logic for better debugging and transparency:

- `google_calendar_event_events.sql` - Calendar events → Nexus events (note:
  double "event")
- `google_calendar_person_identifiers.sql` - Organizer/creator/attendee
  identifiers
- `google_calendar_group_identifiers.sql` - Domain identifiers (filtered)
- `google_calendar_person_traits.sql` - Participant names and emails
- `google_calendar_group_traits.sql` - Domain names
- `google_calendar_event_relationship_declarations.sql` - Person→domain
  memberships

**Key Pattern:** All intermediate models read directly from normalized tables
without joins. Person/group models read from
`google_calendar_event_participants`, event model reads from
`google_calendar_events_normalized`.

### Layer 4: Union - 4 Models (Nexus Integration)

These models feed directly into the nexus pipeline:

#### `google_calendar_events`

Creates nexus-compatible events:

**Event Classification:**

- `external_meeting` (significance: 3) - Has external attendees
- `internal_meeting` (significance: 2) - Only internal attendees

```sql
event_id               -- Unique event identifier (evt_ prefix)
event_name             -- "external_meeting" or "internal_meeting"
occurred_at            -- Meeting start time
event_description      -- Meeting summary
event_significance     -- 3 for external, 2 for internal
event_type             -- "calendar_event"
source                 -- "google_calendar"
_ingested_at           -- Ingestion timestamp
calendar_event_key     -- iCalUID-based composite key
ical_uid               -- Universal calendar identifier
calendar_event_id      -- Calendar-specific ID
instance_start         -- Instance timestamp (recurring events)
summary                -- Meeting title
description            -- Meeting description
location               -- Meeting location
status                 -- Event status
start_time             -- Start timestamp
end_time               -- End timestamp
is_all_day             -- All-day flag
is_recurring           -- Recurring flag
```

#### `google_calendar_entity_identifiers`

Unified person + group identifiers:

```sql
entity_identifier_id   -- Unique identifier (ent_idfr_ prefix)
event_id               -- Reference to calendar event
edge_id                -- Groups related identifiers
entity_type            -- "person" or "group"
identifier_type        -- "email" or "domain"
identifier_value       -- Email address or domain
role                   -- Participation role (see below)
occurred_at            -- Meeting start time
source                 -- "google_calendar"
_ingested_at           -- Ingestion timestamp
```

**Role Types:**

- Person roles: `organizer`, `creator`, `attendee`
- Group roles: `organizer`, `creator`, `attendee` (for domain tracking)

#### `google_calendar_entity_traits`

Unified person + group traits:

```sql
entity_trait_id        -- Unique trait identifier (ent_tr_ prefix)
event_id               -- Reference to calendar event
entity_type            -- "person" or "group"
identifier_type        -- "email" or "domain"
identifier_value       -- Email address or domain
trait_name             -- "name", "email" (for persons) or "domain_name" (for domains)
trait_value            -- The trait value
occurred_at            -- Meeting start time
source                 -- "google_calendar"
_ingested_at           -- Ingestion timestamp
```

#### `google_calendar_relationship_declarations`

Person→group relationship declarations:

```sql
relationship_declaration_id  -- Unique ID (rel_decl_ prefix)
event_id                     -- Reference to calendar event
occurred_at                  -- Meeting start time
entity_a_identifier          -- Person email address
entity_a_identifier_type     -- "email"
entity_a_type                -- "person"
entity_a_role                -- "organizer", "creator", or "attendee"
entity_b_identifier          -- Email domain
entity_b_identifier_type     -- "domain"
entity_b_type                -- "group"
entity_b_role                -- "organization"
relationship_type            -- "membership"
relationship_direction       -- "a_to_b"
is_active                    -- true
source                       -- "google_calendar"
```

**Filtered Generic Domains:**

- gmail.com, yahoo.com, hotmail.com, outlook.com
- aol.com, icloud.com, me.com, live.com, msn.com
- googlemail.com, ymail.com, rocketmail.com, protonmail.com
- mail.com, zoho.com

## Cross-Account Deduplication

Google Calendar uses `iCalUID` for cross-account deduplication, similar to
Gmail's `Message-ID` header:

### Single Events

- **Primary Key**: `iCalUID`
- **Deduplication**: Events with the same `iCalUID` across different calendars
  are treated as the same event
- **Use Case**: Same event appearing in organizer's and invitees' calendars

### Recurring Events

- **Primary Key**: `iCalUID + instanceStart`
- **Instance Start**: Determined from `originalStartTime.dateTime` (if present),
  otherwise `start.dateTime` or `start.date`
- **Deduplication**: Each instance of a recurring event is unique, but all
  instances share the same `iCalUID`
- **Use Case**: Weekly meetings with specific instances (e.g., exceptions,
  cancellations)

### Event Key Structure

```sql
-- Single event
event_id = ical_uid
-- Example: "event_abc123@google.com"

-- Recurring event instance
event_id = ical_uid || '|' || CAST(instance_start AS STRING)
-- Example: "event_abc123@google.com|2024-01-15 10:00:00"
```

This ensures the same meeting (identified by `iCalUID`) appearing in multiple
calendars is only counted once, while recurring event instances are properly
distinguished.

## Use Cases

### Meeting Analytics

```sql
-- External meeting frequency by person
SELECT
    e.name,
    e.email,
    COUNT(DISTINCT ev.event_id) as external_meetings,
    COUNT(DISTINCT DATE(ev.occurred_at)) as meeting_days,
    MAX(ev.occurred_at) as last_meeting
FROM {{ ref('nexus_entities') }} e
JOIN {{ ref('nexus_entity_identifiers') }} ei
    ON ei.identifier_value = e.email
JOIN {{ ref('nexus_events') }} ev
    ON ev.event_id = ei.event_id
WHERE e.entity_type = 'person'
  AND ev.source = 'google_calendar'
  AND ev.event_name = 'external_meeting'
  AND ev.occurred_at >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY e.entity_id, e.name, e.email
ORDER BY external_meetings DESC;
```

### Recurring Event Analysis

```sql
-- Analyze recurring vs one-time meetings
SELECT
    CASE
        WHEN is_recurring THEN 'recurring'
        ELSE 'one-time'
    END as meeting_type,
    COUNT(DISTINCT ical_uid) as unique_meetings,
    COUNT(DISTINCT event_id) as total_instances,
    AVG(CASE WHEN is_recurring THEN NULL ELSE 1 END) as avg_one_time,
    AVG(CASE WHEN is_recurring THEN
        COUNT(DISTINCT event_id) OVER (PARTITION BY ical_uid)
    END) as avg_recurring_instances
FROM {{ ref('google_calendar_events_normalized') }}
WHERE start_time >= CURRENT_DATE - INTERVAL 90 DAY
GROUP BY meeting_type;
```

### Customer Engagement Tracking

```sql
-- Track meetings with specific customer domain
SELECT
    ev.occurred_at,
    ev.event_description as meeting_title,
    ev.is_recurring,
    COUNT(DISTINCT CASE WHEN e.domain = 'client.com' THEN e.entity_id END) as client_attendees,
    COUNT(DISTINCT CASE WHEN e.domain IN ('yourcompany.com') THEN e.entity_id END) as internal_attendees
FROM {{ ref('nexus_events') }} ev
JOIN {{ ref('nexus_entity_identifiers') }} ei ON ev.event_id = ei.event_id
JOIN {{ ref('nexus_entities') }} e
    ON ei.identifier_value IN (e.email, e.domain)
WHERE ev.source = 'google_calendar'
  AND EXISTS (
      SELECT 1 FROM {{ ref('nexus_entity_identifiers') }} ei2
      WHERE ei2.event_id = ev.event_id
        AND ei2.identifier_value = 'client.com'
        AND ei2.entity_type = 'group'
  )
GROUP BY ev.event_id, ev.occurred_at, ev.event_description, ev.is_recurring
ORDER BY ev.occurred_at DESC;
```

## Performance Optimization

### Incremental Processing

For large calendar datasets:

```yaml
models:
  nexus:
    sources:
      google_calendar:
        +materialized: incremental
        +unique_key: event_id
        +cluster_by: ["occurred_at"]
```

### Partitioning (BigQuery)

Optimize time-based queries:

```yaml
models:
  nexus:
    sources:
      google_calendar:
        +partition_by:
          {
            "field": "occurred_at",
            "data_type": "timestamp",
            "granularity": "day",
          }
```

## Troubleshooting

### Common Issues

**1. No calendar events appearing**

- Check `nexus.google_calendar.enabled: true` is set
- Verify source table exists with STANDARD_TABLE_SCHEMA structure
- Ensure `iCalUID` is present in raw JSON records
- Check that source data has the expected JSON structure

**2. All meetings classified as internal**

- Verify `internal_domains` variable includes your company domains
- Check that external attendees have different domains

**3. Missing attendees**

- Verify attendee emails are not null/empty in source JSON
- Check that attendee parsing is working correctly
- Ensure participant normalization is enabled

**4. Duplicate events across calendars**

- Verify `iCalUID` is being used correctly for deduplication
- Check that recurring event instances use `instanceStart` in composite key
- Ensure `QUALIFY` clause is deduplicating properly

### Debugging Queries

```sql
-- Check raw source data
SELECT
    _raw_record,
    _ingested_at,
    _connection_id,
    _stream_id
FROM {{ source('google_calendar', 'google_calendar_events') }}
LIMIT 5;

-- Verify base model processing
SELECT * FROM {{ ref('google_calendar_events_base') }}
LIMIT 10;

-- Check normalized events with deduplication
SELECT
    event_id,
    ical_uid,
    calendar_event_id,
    is_recurring,
    instance_start,
    summary,
    start_time
FROM {{ ref('google_calendar_events_normalized') }}
ORDER BY start_time DESC
LIMIT 10;

-- Verify participants extraction
SELECT
    event_id,
    email,
    role,
    domain
FROM {{ ref('google_calendar_event_participants') }}
LIMIT 20;

-- Check meeting classification
SELECT
    event_name,
    is_recurring,
    COUNT(*) as event_count
FROM {{ ref('google_calendar_events') }}
GROUP BY event_name, is_recurring;
```

## Advanced Configuration

### Custom Meeting Classification

Override the external meeting detection logic:

```sql
-- Custom significance scoring
CASE
    WHEN has_external_attendees AND ARRAY_LENGTH(attendees) > 5 THEN 4
    WHEN has_external_attendees THEN 3
    WHEN ARRAY_LENGTH(attendees) > 10 THEN 2
    ELSE 1
END as significance
```

### Meeting Type Detection

Add custom event types based on meeting content:

```sql
-- Enhanced event naming
CASE
    WHEN LOWER(summary) LIKE '%interview%' THEN 'interview'
    WHEN LOWER(summary) LIKE '%demo%' THEN 'product_demo'
    WHEN has_external_attendees THEN 'external_meeting'
    ELSE 'internal_meeting'
END as event_name
```

### Recurring Event Handling

Customize how recurring events are processed:

```sql
-- Filter to only recurring events
SELECT * FROM {{ ref('google_calendar_events_normalized') }}
WHERE is_recurring = true;

-- Get master recurring events (no instanceStart variation)
SELECT DISTINCT
    ical_uid,
    summary,
    COUNT(DISTINCT instance_start) as instance_count
FROM {{ ref('google_calendar_events_normalized') }}
WHERE is_recurring = true
GROUP BY ical_uid, summary;
```

## Migration Guide

### From Custom Calendar Models

If you have existing custom Google Calendar models:

1. **Backup Current Models**: Save your existing logic
2. **Compare Schemas**: Ensure data compatibility with STANDARD_TABLE_SCHEMA
3. **Verify iCalUID**: Ensure your source data includes `iCalUID` field
4. **Enable Template Source**: Configure to point to your data
5. **Test Output**: Verify data quality, deduplication, and completeness
6. **Update References**: Change refs to use template models
7. **Remove Custom Models**: Clean up old source models

### Schema Compatibility

Ensure your calendar data includes:

- Event start/end times
- `iCalUID` for cross-account deduplication
- Organizer and attendee information
- Meeting summaries and descriptions
- Response status for attendees
- Recurring event indicators (`recurringEventId` or `recurrence` array)

### StandarD_TABLE_SCHEMA Migration

If migrating from old schema with `record` and `synced_at`:

```sql
-- Example migration query
CREATE OR REPLACE TABLE `new_table` AS
SELECT
    TO_JSON_STRING(old_record) as _raw_record,
    synced_at as _ingested_at,
    'connection_123' as _connection_id,
    'calendar_abc' as _stream_id,
    synced_at as _sync_timestamp,
    NULL as _sync_token
FROM `old_table`;
```

---

**Ready to integrate Google Calendar?** Set
`nexus.google_calendar.enabled: true` and run `dbt build`!
