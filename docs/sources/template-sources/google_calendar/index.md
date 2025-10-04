---
title: Google Calendar Template Source
tags: [template-sources, google-calendar, calendar, meetings, configuration]
summary:
  Ready-to-use Google Calendar integration for meeting events, attendee
  tracking, and organization relationships
---

# Google Calendar Template Source

The **Google Calendar Template Source** provides instant integration with Google
Calendar data through domain-wide delegation or ETL pipelines. It processes
calendar events into meeting events, extracts attendee information, and
identifies internal vs external meetings - all through simple configuration.

## Overview

The Google Calendar template source transforms raw calendar data into the nexus
framework:

- **📅 Meeting Events**: Each calendar event becomes an `external_meeting` or
  `internal_meeting`
- **👥 Attendee Tracking**: Extracts organizers, creators, and attendees as
  participants
- **🏢 Organization Detection**: Creates groups from attendee email domains
- **🔗 Participation Links**: Connects people to meetings they attended
- **🏷️ Meeting Context**: Captures meeting details and external participant
  flags

## Architecture

```
Calendar Events (JSON) → Base Model → Events + Identifiers + Traits + Memberships
                                  ↓
                            Nexus Framework → Final Tables
```

### Data Flow

1. **Data Sync**: Calendar events synced to your data warehouse via domain-wide
   delegation or ETL
2. **Base Processing**: `google_calendar_events_base.sql` transforms JSON to
   structured data
3. **Event Creation**: Each event = 1 `external_meeting` or `internal_meeting`
   event
4. **Participant Extraction**: Organizer, creator + attendees become event
   participants
5. **Identity Resolution**: Email addresses → person identifiers, domains →
   group identifiers
6. **Final Integration**: Auto-included in nexus `events`, `persons`, `groups`
   tables

## File Structure

```
sources/google_calendar/
├── base/
│   └── google_calendar_events_base.sql     # JSON → structured events
├── google_calendar_events.sql              # Events for nexus processing
├── google_calendar_person_identifiers.sql  # Email identifiers
├── google_calendar_person_traits.sql       # Person traits (name, email)
├── google_calendar_group_identifiers.sql   # Domain identifiers
├── google_calendar_group_traits.sql        # Group traits (domain)
├── google_calendar_membership_identifiers.sql # Person-group relationships
└── google_calendar.yml                     # dbt source definition
```

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
SELECT * FROM nexus_events
WHERE source = 'google_calendar'
ORDER BY occurred_at DESC
LIMIT 10;

-- Find external meetings
SELECT
    e.event_description as meeting_title,
    e.occurred_at,
    COUNT(DISTINCT p.id) as attendee_count,
    COUNT(DISTINCT CASE WHEN pp.role = 'organizer' THEN p.id END) as organizer_count,
    COUNT(DISTINCT CASE WHEN pp.role = 'attendee' THEN p.id END) as attendee_count_regular,
    COUNT(DISTINCT CASE WHEN pp.role = 'optional_attendee' THEN p.id END) as optional_attendee_count
FROM nexus_events e
JOIN nexus_person_participants pp ON e.id = pp.event_id
JOIN nexus_persons p ON pp.person_id = p.id
WHERE e.source = 'google_calendar'
AND e.event_name = 'external_meeting'
GROUP BY e.id, e.event_description, e.occurred_at
ORDER BY e.occurred_at DESC;
```

## Configuration

### Basic Configuration

```yaml
# dbt_project.yml
vars:
  nexus:
    google_calendar:
      enabled: true
      # Uses defaults: schema=google_calendar, table=calendar_events
```

### Custom Source Location

```yaml
vars:
  nexus:
    google_calendar:
      enabled: true
      location:
        schema: slide-rule-tech-nexus.google_workspace
        table: calendar_events
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

Your Google Calendar source table must have this structure:

```sql
CREATE TABLE `project.schema.table` (
  connection_id STRING NOT NULL,      -- Connection identifier
  first_seen_at TIMESTAMP NOT NULL,   -- When record was first seen
  last_modified_at STRING NOT NULL,   -- When record was last modified
  last_action STRING NOT NULL,        -- Last action performed
  deleted_at TIMESTAMP,               -- When record was deleted (nullable)
  cursor STRING NOT NULL,             -- Sync cursor for incremental processing
  record JSON NOT NULL,               -- Google Calendar event as JSON
  synced_at TIMESTAMP NOT NULL        -- When the record was synced
);
```

**Key Features:**

- **Deleted record handling**: `deleted_at` field allows filtering out deleted
  events
- **Incremental sync support**: `cursor` field enables efficient incremental
  processing
- **Change tracking**: `last_modified_at` and `last_action` provide audit trail
- **Domain-wide delegation compatible**: Supports organization-wide calendar
  access

### Google Calendar Event JSON Structure

The `record` column should contain Google Calendar API event format:

```json
{
  "id": "event_id_123",
  "summary": "Team Meeting",
  "description": "Weekly team sync",
  "location": "Conference Room A",
  "start": {
    "dateTime": "2024-01-15T10:00:00-08:00"
  },
  "end": {
    "dateTime": "2024-01-15T11:00:00-08:00"
  },
  "organizer": {
    "email": "organizer@company.com",
    "displayName": "Meeting Organizer"
  },
  "creator": {
    "email": "creator@company.com",
    "displayName": "Event Creator"
  },
  "attendees": [
    {
      "email": "attendee1@company.com",
      "displayName": "Internal Attendee",
      "responseStatus": "accepted"
    },
    {
      "email": "external@client.com",
      "displayName": "External Attendee",
      "responseStatus": "accepted"
    }
  ]
}
```

## Generated Models

### Base Model: `google_calendar_events_base`

Transforms raw Google Calendar JSON into structured events:

**Key Features:**

- **Deleted record filtering**: Automatically excludes deleted events using
  `deleted_at` field
- Parses start/end times (handles both dateTime and date formats)
- Extracts organizer, creator, and attendee information
- Detects external meetings based on `internal_domains`
- Creates structured arrays for attendees with metadata
- Deduplicates events by latest start time
- **Domain-wide delegation support**: Works with organization-wide calendar
  access

**Output Schema:**

```sql
nexus_event_id         -- Unique identifier for nexus processing
calendar_event_id      -- Original Google Calendar event ID
summary                -- Meeting title
description            -- Meeting description
location               -- Meeting location
status                 -- Event status (confirmed, tentative, cancelled)
user_email             -- Email of user whose calendar this event came from (domain-wide delegation)
calendar_id            -- Calendar ID where the event resides
start_time             -- Meeting start timestamp
end_time               -- Meeting end timestamp
is_all_day             -- Boolean for all-day events
organizer              -- STRUCT with email, name, domain, is_internal
creator                -- STRUCT with email, name, domain, is_internal
attendees              -- ARRAY of attendee STRUCTs
has_external_attendees -- Boolean for external meeting detection
event_name             -- "external_meeting" or "internal_meeting"
event_description      -- Meeting summary
source                 -- "google_calendar"
```

### Events: `google_calendar_events`

Creates nexus-compatible events:

**Event Classification:**

- `external_meeting` (significance: 3) - Has external attendees
- `internal_meeting` (significance: 2) - Only internal attendees

```sql
event_id               -- Reference to calendar event
event_name             -- "external_meeting" or "internal_meeting"
occurred_at            -- Meeting start time
event_description      -- Meeting summary
significance           -- 3 for external, 2 for internal
event_type             -- "calendar_event"
source                 -- "google_calendar"
```

### Person Identifiers: `google_calendar_person_identifiers`

Extracts email addresses from all meeting participants with role context:

**Role Types:**

- `organizer` - Person who organized the meeting
- `creator` - Person who created the calendar event
- `attendee` - Person who attended the meeting
- `optional_attendee` - Person who was optionally invited

**Sources:**

- Meeting organizer email
- Meeting creator email
- All attendee emails

```sql
event_id               -- Reference to calendar event
edge_id                 -- Groups related identifiers
identifier_type        -- "email"
identifier_value       -- Email address
role                   -- "organizer", "creator", "attendee", or "optional_attendee"
occurred_at            -- Meeting start time
source                 -- "google_calendar"
```

### Person Traits: `google_calendar_person_traits`

Captures participant information:

**Trait Types:**

- `email` - Email address
- `display_name` - Display name from calendar

```sql
event_id               -- Reference to calendar event
edge_id                 -- Groups related traits
trait_name             -- "email" or "display_name"
trait_value            -- The trait value
occurred_at            -- Meeting start time
source                 -- "google_calendar"
```

### Group Identifiers: `google_calendar_group_identifiers`

Creates groups from email domains (excludes generic domains):

**Generic Domain Filter:** Automatically excludes common email providers:

- gmail.com, yahoo.com, hotmail.com, outlook.com
- aol.com, icloud.com, me.com, live.com, msn.com
- googlemail.com, ymail.com, rocketmail.com, protonmail.com
- mail.com, zoho.com

```sql
event_id               -- Reference to calendar event
edge_id                 -- Groups related identifiers
identifier_type        -- "domain"
identifier_value       -- Email domain
occurred_at            -- Meeting start time
source                 -- "google_calendar"
```

### Group Traits: `google_calendar_group_traits`

Domain information for organizations:

```sql
event_id               -- Reference to calendar event
edge_id                 -- Groups related traits
trait_name             -- "domain"
trait_value            -- Domain name
occurred_at            -- Meeting start time
source                 -- "google_calendar"
```

### Membership Identifiers: `google_calendar_membership_identifiers`

Links people to organizations via meeting participation:

**Role Types:**

- `organizer` - Meeting organizer
- `creator` - Meeting creator
- `attendee` - Meeting attendee
- `optional_attendee` - Optional meeting attendee

```sql
event_id               -- Reference to calendar event
occurred_at            -- Meeting start time
person_identifier      -- Email address
person_identifier_type -- "email"
group_identifier       -- Email domain
group_identifier_type  -- "domain"
role                   -- Participation role
source                 -- "google_calendar"
```

## Use Cases

### Meeting Analytics

```sql
-- External meeting frequency by person
SELECT
    p.name,
    p.email,
    COUNT(*) as external_meetings,
    COUNT(DISTINCT DATE(e.occurred_at)) as meeting_days
FROM nexus_events e
JOIN nexus_person_participants pp ON e.id = pp.event_id
JOIN nexus_persons p ON pp.person_id = p.id
WHERE e.source = 'google_calendar'
AND e.event_name = 'external_meeting'
AND e.occurred_at >= current_date - interval 30 days
GROUP BY p.name, p.email
ORDER BY external_meetings DESC;
```

### Customer Engagement Tracking

```sql
-- Track meetings with specific customer domain
SELECT
    e.occurred_at,
    e.event_description as meeting_title,
    COUNT(DISTINCT CASE WHEN rpi.identifier_value LIKE '%@client.com' THEN p.id END) as client_attendees,
    COUNT(DISTINCT CASE WHEN rpi.identifier_value LIKE '%@yourcompany.com' THEN p.id END) as internal_attendees
FROM nexus_events e
JOIN nexus_group_participants gp ON e.id = gp.event_id
JOIN nexus_groups g ON gp.group_id = g.id
JOIN nexus_person_participants pp ON e.id = pp.event_id
JOIN nexus_persons p ON pp.person_id = p.id
JOIN nexus_resolved_person_identifiers rpi ON p.id = rpi.person_id
WHERE e.source = 'google_calendar'
AND g.domain = 'client.com'
GROUP BY e.id, e.occurred_at, e.event_description
ORDER BY e.occurred_at DESC;
```

### Domain-Wide Delegation Analytics

```sql
-- Analyze meeting patterns by calendar owner
SELECT
    base.user_email as calendar_owner,
    COUNT(*) as total_meetings,
    COUNT(CASE WHEN base.has_external_attendees THEN 1 END) as external_meetings,
    ROUND(COUNT(CASE WHEN base.has_external_attendees THEN 1 END) * 100.0 / COUNT(*), 2) as external_meeting_pct,
    COUNT(DISTINCT DATE(base.start_time)) as active_days
FROM {{ ref('google_calendar_events_base') }} base
WHERE base.start_time >= current_date - interval 30 days
GROUP BY base.user_email
ORDER BY total_meetings DESC;

-- Find cross-calendar collaboration patterns
SELECT
    organizer.user_email as organizer_calendar,
    attendee_calendar.user_email as attendee_calendar,
    COUNT(*) as shared_meetings
FROM {{ ref('google_calendar_events_base') }} organizer
JOIN {{ ref('google_calendar_events_base') }} attendee_calendar
  ON organizer.calendar_event_id = attendee_calendar.calendar_event_id
  AND organizer.user_email != attendee_calendar.user_email
WHERE organizer.start_time >= current_date - interval 30 days
GROUP BY organizer.user_email, attendee_calendar.user_email
HAVING COUNT(*) >= 5
ORDER BY shared_meetings DESC;
```

## Integration with Nexus

### Automatic Processing

When enabled, Google Calendar models automatically integrate with nexus:

1. **Events** → `nexus_events` table
2. **Person Identifiers** → Identity resolution → `nexus_persons`
3. **Group Identifiers** → Identity resolution → `nexus_groups`
4. **Memberships** → `nexus_memberships` table

### Final Table Access

```sql
-- View all calendar events
SELECT * FROM nexus_events
WHERE source = 'google_calendar'
ORDER BY occurred_at DESC;

-- Find external meetings
SELECT * FROM nexus_events
WHERE source = 'google_calendar'
AND event_name = 'external_meeting'
ORDER BY occurred_at DESC;

-- See calendar participants
SELECT
    e.event_description,
    e.occurred_at,
    p.name,
    p.email
FROM nexus_events e
JOIN nexus_person_participants pp ON e.id = pp.event_id
JOIN nexus_persons p ON pp.person_id = p.id
WHERE e.source = 'google_calendar'
ORDER BY e.occurred_at DESC;

-- View events by calendar owner (domain-wide delegation)
SELECT
    user_email as calendar_owner,
    COUNT(*) as event_count,
    COUNT(CASE WHEN has_external_attendees THEN 1 END) as external_meetings
FROM {{ ref('google_calendar_events_base') }}
GROUP BY user_email
ORDER BY event_count DESC;
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
        +incremental_strategy: merge
        +cluster_by: ["occurred_at"]
```

### Clustering

Improve query performance with clustering:

```yaml
models:
  nexus:
    sources:
      google_calendar:
        +cluster_by: ["occurred_at", "source"]
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
- Verify source table exists and location is correctly configured
- Ensure source data has the expected JSON structure
- Check that `deleted_at IS NULL` filter isn't excluding all events

**2. All meetings classified as internal**

- Verify `internal_domains` variable includes your company domains
- Check that external attendees have different domains

**3. Missing attendees**

- Verify attendee emails are not null/empty in source JSON
- Check that attendee parsing is working correctly

### Debugging Queries

```sql
-- Check raw source data
SELECT * FROM {{ nexus_source('google_calendar', 'calendar_events') }} LIMIT 5;

-- Check for deleted events
SELECT
  COUNT(*) as total_events,
  COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) as active_events,
  COUNT(CASE WHEN deleted_at IS NOT NULL THEN 1 END) as deleted_events
FROM {{ nexus_source('google_calendar', 'calendar_events') }};

-- Verify base model processing
SELECT
    calendar_event_id,
    summary,
    has_external_attendees,
    ARRAY_LENGTH(attendees) as attendee_count
FROM {{ ref('google_calendar_events_base') }}
LIMIT 10;

-- Check meeting classification
SELECT
    event_name,
    COUNT(*) as event_count
FROM {{ ref('google_calendar_events') }}
GROUP BY event_name;
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

## Migration Guide

### From Custom Calendar Models

If you have existing custom Google Calendar models:

1. **Backup Current Models**: Save your existing logic
2. **Compare Schemas**: Ensure data compatibility
3. **Enable Template Source**: Configure to point to your data
4. **Test Output**: Verify data quality and completeness
5. **Update References**: Change refs to use template models
6. **Remove Custom Models**: Clean up old source models

### Schema Compatibility

Ensure your calendar data includes:

- Event start/end times
- Organizer and attendee information
- Meeting summaries and descriptions
- Response status for attendees

---

**Ready to integrate Google Calendar?** Set
`nexus.google_calendar.enabled: true` and run `dbt build`!
