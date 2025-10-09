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
GROUP BY ev.event_id, ev.event_description, ev.occurred_at
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
      # Uses defaults: schema=google_calendar, table=calendar_events
```

### Custom Source Location

```yaml
vars:
  nexus:
    google_calendar:
      enabled: true
      location:
        schema: my_calendar_data
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
  record JSON,           -- Google Calendar event as JSON
  synced_at TIMESTAMP    -- When the record was synced
);
```

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

Google Calendar uses the **four-layer source architecture** with special naming
to avoid conflicts:

### Layer 1: Base - `google_calendar_events_base.sql`

Transforms raw Google Calendar JSON into structured events.

**Key Features:**

- Parses start/end times (handles both dateTime and date formats)
- Extracts organizer, creator, and attendee information
- Detects external meetings based on `internal_domains`
- Creates structured arrays for attendees with metadata

### Layer 2: Normalized - `google_calendar_events_normalized.sql`

Clean, deduplicated calendar events ready for processing.

**Special naming**: Note the `_normalized` suffix to avoid conflict with
"events" concept.

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

**Special naming**: `google_calendar_event_events` uses double "event" -
calendar events transformed into nexus events.

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
```

**Role Types:**

- Person roles: `organizer`, `creator`, `attendee`
- Group roles: `organizer_domain`, `creator_domain`, `attendee_domain`

#### `google_calendar_entity_traits`

Unified person + group traits:

```sql
entity_trait_id        -- Unique trait identifier (ent_tr_ prefix)
event_id               -- Reference to calendar event
entity_type            -- "person" or "group"
identifier_type        -- "email" or "domain"
identifier_value       -- Email address or domain
trait_name             -- "name", "email" (for persons) or "name" (for domains)
trait_value            -- The trait value
role                   -- Participation role
occurred_at            -- Meeting start time
source                 -- "google_calendar"
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
entity_a_role                -- "member"
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

### Customer Engagement Tracking

```sql
-- Track meetings with specific customer domain
SELECT
    ev.occurred_at,
    ev.event_description as meeting_title,
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
GROUP BY ev.event_id, ev.occurred_at, ev.event_description
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
- Verify source table exists: `google_calendar.calendar_events`
- Ensure source data has the expected JSON structure

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
