# Google Calendar Source Documentation

This document describes the Google Calendar source integration for the nexus
framework, which processes calendar events from Google Calendar via Nango
integration into events, person/group identifiers, traits, and event
participation relationships.

## Overview

The Google Calendar source follows the established nexus framework patterns but
includes unique calendar-specific processing:

- Raw data comes from BigQuery `google_calendar.calendar_events` table with JSON
  records
- Base model transforms Google Calendar API responses into structured events
- Each calendar event becomes either an `external_meeting` or `internal_meeting`
  event
- Email addresses are parsed for person identifiers and domain extraction for
  groups
- Generic email domains (gmail.com, etc.) are filtered out from group creation
- Event participation creates many-to-many relationships between persons and
  calendar events

## Architecture

```
Calendar Events (JSON) → Base Model → Events + Identifiers + Traits + Memberships
                                  ↓
                            Nexus Framework → Final Tables
```

### Data Flow

1. **Nango Sync**: `google-calendar` integration syncs calendar events to
   BigQuery
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
├── google_calendar.yml                     # dbt source definition
└── GOOGLE_CALENDAR_SOURCE.md              # This documentation
```

## Configuration

### Enabling the Source

```yaml
# dbt_project.yml
vars:
  nexus:
    google_calendar:
      enabled: true
      # Optional: Override default source location
      # location:
      #   schema: my_calendar_schema    # Default: google_calendar
      #   table: my_calendar_table      # Default: calendar_events
```

### Required Variables

```yaml
vars:
  # Required: Define internal email domains for external meeting detection
  internal_domains: ["yourcompany.com", "subsidiary.com"]
```

## Data Models

### Base Model: `google_calendar_events_base.sql`

Transforms raw Google Calendar JSON into structured event data:

**Key Transformations:**

- Parses event times (handles both dateTime and date formats)
- Extracts organizer, creator, and attendee information
- Determines internal vs external meetings based on `internal_domains`
- Creates structured arrays for attendees with response status
- Deduplicates events based on latest `start_time`

**Output Schema:**

```sql
nexus_event_id          -- Surrogate key for nexus processing
calendar_event_id       -- Original Google Calendar event ID
summary                 -- Event title
description            -- Event description
location               -- Event location
start_time             -- Event start timestamp
end_time               -- Event end timestamp
is_all_day             -- Boolean for all-day events
organizer              -- STRUCT with email, name, domain, is_internal
creator                -- STRUCT with email, name, domain, is_internal
attendees              -- ARRAY of attendee STRUCTs
has_external_attendees -- Boolean for external meeting detection
event_name             -- "external_meeting" or "internal_meeting"
event_description      -- Summary or "Calendar Event"
source                 -- "google_calendar"
```

### Events: `google_calendar_events.sql`

Creates nexus-compatible events from base model:

**Event Types:**

- `external_meeting` (significance: 3) - Has external attendees
- `internal_meeting` (significance: 2) - Only internal attendees

**Output Schema:**

```sql
event_id               -- nexus_event_id from base
event_name             -- "external_meeting" or "internal_meeting"
occurred_at            -- start_time
event_description      -- Event summary or "Calendar Event"
event_value            -- null
value_unit             -- null
event_significance     -- 3 for external, 2 for internal
event_type             -- "calendar_event"
source                 -- "google_calendar"
source_table           -- "google_calendar_events"
synced_at              -- When data was synced
realtime_processed     -- null (batch processing)
```

### Person Identifiers: `google_calendar_person_identifiers.sql`

Extracts email addresses from organizer, creator, and attendees:

**Sources:**

- Event organizer email
- Event creator email
- All attendee emails

**Output Schema:**

```sql
event_id               -- Reference to calendar event
edge_id                 -- Surrogate key for grouping
identifier_type        -- Always "email"
identifier_value       -- Email address
occurred_at            -- Event start time
source                 -- "google_calendar"
```

### Person Traits: `google_calendar_person_traits.sql`

Extracts person traits from calendar participants:

**Trait Types:**

- `email` - Email address
- `display_name` - Display name from calendar

**Sources:**

- Organizer email and display name
- Creator email and display name
- Attendee emails and display names

**Output Schema:**

```sql
event_id               -- Reference to calendar event
edge_id                 -- Links related traits for same person
trait_name             -- "email" or "display_name"
trait_value            -- The trait value
occurred_at            -- Event start time
source                 -- "google_calendar"
```

### Group Identifiers: `google_calendar_group_identifiers.sql`

Extracts email domains as group identifiers (excluding generic domains):

**Generic Domain Filter:** Excludes common email providers:

- gmail.com, yahoo.com, hotmail.com, outlook.com
- aol.com, icloud.com, me.com, live.com, msn.com
- googlemail.com, ymail.com, rocketmail.com, protonmail.com
- mail.com, zoho.com

**Sources:**

- Organizer email domain
- Creator email domain
- Attendee email domains

**Output Schema:**

```sql
event_id               -- Reference to calendar event
edge_id                 -- Surrogate key for grouping
identifier_type        -- Always "domain"
identifier_value       -- Email domain (e.g., "company.com")
occurred_at            -- Event start time
source                 -- "google_calendar"
```

### Group Traits: `google_calendar_group_traits.sql`

Creates domain traits for identified groups:

**Trait Types:**

- `domain` - The domain name

**Output Schema:**

```sql
event_id               -- Reference to calendar event
edge_id                 -- Links to group identifier
trait_name             -- Always "domain"
trait_value            -- Domain name
occurred_at            -- Event start time
source                 -- "google_calendar"
```

### Membership Identifiers: `google_calendar_membership_identifiers.sql`

Creates person-to-group relationships based on email domains:

**Relationship Types:**

- `organizer` - Event organizer
- `creator` - Event creator
- `attendee` - Event attendee

**Output Schema:**

```sql
event_id                    -- Reference to calendar event
occurred_at                 -- Event start time
person_identifier           -- Email address
person_identifier_type      -- Always "email"
group_identifier            -- Email domain
group_identifier_type       -- Always "domain"
role                        -- "organizer", "creator", or "attendee"
source                      -- "google_calendar"
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
```

## Configuration Examples

### Basic Setup

```yaml
# dbt_project.yml
vars:
  nexus_enable_google_calendar: true
  internal_domains: ["mycompany.com"]

  sources:
    - name: "google_calendar"
      events: true
      persons: true
      groups: true
      memberships: true
```

### Advanced Configuration

```yaml
vars:
  nexus_enable_google_calendar: true

  # Multiple internal domains
  internal_domains:
    - "company.com"
    - "subsidiary.com"
    - "division.company.com"

  sources:
    - name: "google_calendar"
      events: true
      persons: true
      groups: true
      memberships: true

# Custom materialization
models:
  nexus:
    sources:
      google_calendar:
        +materialized: incremental
        +unique_key: event_id
        +cluster_by: ["occurred_at", "source"]
```

## Troubleshooting

### Common Issues

**1. No events appearing**

- Check `nexus_enable_google_calendar: true` is set
- Verify source table exists: `google_calendar.calendar_events`
- Check `internal_domains` variable is configured

**2. Missing participants**

- Verify attendee emails are not null/empty in source data
- Check that `real_time_event_filter` macro is not filtering too aggressively

**3. Generic domains appearing as groups**

- Check that generic domain filter is working
- Add additional generic domains to the filter list if needed

### Debugging Queries

```sql
-- Check raw source data
SELECT * FROM {{ source('google_calendar', 'calendar_events') }} LIMIT 5;

-- Verify base model processing
SELECT * FROM {{ ref('google_calendar_events_base') }} LIMIT 5;

-- Check event creation
SELECT event_name, COUNT(*)
FROM {{ ref('google_calendar_events') }}
GROUP BY event_name;

-- Verify person identifier extraction
SELECT identifier_type, COUNT(DISTINCT identifier_value)
FROM {{ ref('google_calendar_person_identifiers') }}
GROUP BY identifier_type;
```

## Performance Considerations

### Incremental Processing

For large calendar datasets, consider incremental materialization:

```yaml
models:
  nexus:
    sources:
      google_calendar:
        +materialized: incremental
        +unique_key: event_id
        +incremental_strategy: merge
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

For time-based queries:

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
