# Google Calendar Source Documentation

This document describes the Google Calendar source integration for the CRM
warehouse, which processes calendar events from Google Calendar via Nango
integration into events, person/group identifiers, traits, and event
participation relationships.

## Overview

The Google Calendar source follows the established nexus framework patterns but
includes unique calendar-specific processing:

- Raw data comes from BigQuery
  `sliderule-analytics.google_calendar.calendar_events` table with JSON records
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
├── google_calendar.yml                                 # Source definition
├── base/
│   └── google_calendar_events_base.sql                # JSON transformation & deduplication
├── google_calendar_events.sql                         # Event model
├── google_calendar_person_identifiers.sql             # Email extraction for persons
├── google_calendar_group_identifiers.sql              # Domain extraction for groups
├── google_calendar_person_traits.sql                  # Person email/name traits
├── google_calendar_group_traits.sql                   # Group domain traits
├── google_calendar_membership_identifiers.sql         # Event participation
└── GOOGLE_CALENDAR_SOURCE.md                          # This documentation
```

## Key Models

### Base Model (`google_calendar_events_base.sql`)

Transforms raw Google Calendar JSON into structured fields:

```sql
-- Extracts event_id from JSON
-- Applies real-time filtering on event_id
-- Generates nexus_event_id for internal use
-- Parses start/end times, summary, description, location
-- Processes organizer, creator, and attendees arrays
-- Determines internal vs external meeting classification
-- Deduplicates on calendar_event_id (latest occurrence)
-- Adds source = 'google_calendar'
```

**Key Fields:**

- `nexus_event_id`: Generated surrogate key from calendar event_id
- `calendar_event_id`: Google Calendar event ID from JSON
- `summary`: Event title/summary
- `description`: Event description
- `location`: Event location
- `start_time`/`end_time`: Event timing
- `organizer`/`creator`: Event organizer and creator info
- `attendees`: Array of attendee information
- `has_external_attendees`: Boolean indicating external participants

### Events Model (`google_calendar_events.sql`)

Creates standardized events from calendar events:

```sql
-- event_name: 'external_meeting' if has external attendees, 'internal_meeting' if all internal
-- event_type: 'calendar_event'
-- event_significance: 'high' for external meetings, 'medium' for internal
-- source: 'google_calendar'
-- source_table: 'google_calendar_events'
```

### Person Identifiers (`google_calendar_person_identifiers.sql`)

Extracts email addresses as person identifiers:

```sql
-- Organizer: Direct extraction of organizer email
-- Creator: Direct extraction of creator email
-- Attendees: Extraction from attendees array
-- identifier_type: 'email' for all
-- Creates one identifier per email address
```

**Processing:**

1. **Organizer**: Direct extraction from organizer.email
2. **Creator**: Direct extraction from creator.email
3. **Attendees**: `UNNEST(attendees)` + extraction
4. **Union**: Combines organizer + creator + all attendees

### Group Identifiers (`google_calendar_group_identifiers.sql`)

Extracts non-generic domains as group identifiers:

```sql
-- Regex extraction: domain from email addresses
-- Generic domain filtering (gmail.com, yahoo.com, etc.)
-- identifier_type: 'domain'
-- Only creates groups for business domains
```

**Generic Domains Excluded:**

- gmail.com, yahoo.com, hotmail.com, outlook.com
- aol.com, icloud.com, me.com, live.com, msn.com
- googlemail.com, ymail.com, rocketmail.com
- protonmail.com, mail.com, zoho.com

### Person Traits (`google_calendar_person_traits.sql`)

Maps email addresses and display names to person traits:

```sql
-- Organizer/Creator/Attendees: email and display_name traits
-- trait_name: 'email' or 'display_name'
-- trait_value: email address or display name
-- Creates traits for each participant
```

### Group Traits (`google_calendar_group_traits.sql`)

Maps domains to group traits:

```sql
-- domain trait: Maps domain to itself
-- type trait: All domains get type = 'organization'
-- Only non-generic domains included
```

### Event Participation (`google_calendar_membership_identifiers.sql`)

Creates many-to-many relationships between persons and calendar events:

```sql
-- Organizer: role = 'organizer'
-- Creator: role = 'creator'
-- Attendees: role = 'attendee', 'optional_attendee', or 'organizer'
-- Links person_identifier (email) to event_id
-- Enables "show all calendar events this person participated in"
```

## Calendar Event Processing Logic

### Meeting Classification

Calendar events are classified based on attendee domains:

```sql
-- External Meeting: Has at least one attendee with non-internal domain
-- Internal Meeting: All attendees have internal domains (slideruleanalytics.com)
-- Classification determines event_name and significance level
```

### Attendee Processing

Google Calendar provides attendees as a JSON array. The models handle this by:

```sql
-- Unnest attendees array
SELECT event_id, attendee.email, attendee.displayName, attendee.responseStatus
FROM google_calendar_events_base,
UNNEST(attendees) as attendee
WHERE attendee.email IS NOT NULL AND attendee.email != ''
```

### Domain Extraction & Filtering

```sql
-- Extract domain from email
REGEXP_EXTRACT(email_address, r'@(.+)') as domain

-- Filter out generic providers
WHERE domain NOT IN (SELECT domain FROM generic_domains)
```

### Event Participation Strategy

**Single Event, Multiple Participants:**

- 1 calendar event = 1 `external_meeting` or `internal_meeting` event
- Organizer + creator + all attendees linked via `membership_identifiers`
- Same event appears for all involved parties
- Roles distinguish participation type (`organizer`, `creator`, `attendee`,
  `optional_attendee`)

## Integration with Nexus Framework

### Sources Configuration (`dbt_project.yml`)

```yaml
sources:
  - name: google_calendar
    events: true # Include in nexus_events
    groups: true # Include in group resolution
    persons: true # Include in person resolution
    memberships: true # Include in membership tracking
```

### Auto-Inclusion

Google Calendar models are automatically included in:

- `nexus_events`: All `external_meeting` and `internal_meeting` events
- `nexus_person_identifiers`: All email addresses from
  organizer/creator/attendees
- `nexus_group_identifiers`: All non-generic domains
- `nexus_membership_identifiers`: All event participation

## Nango Integration

### Sync Configuration (`syncAllSourceJob.ts`)

```typescript
{
  connectionId: process.env.GADGET_NANGO_GOOGLE_CALENDAR_CONNECTION_ID,
  providerConfigKey: "google-calendar",
  listAll: true,
  model: "GoogleCalendarEvent",
  datasetId: "google_calendar",
  tableId: "calendar_events"
}
```

### Expected JSON Structure

```json
{
  "id": "event_id",
  "summary": "Meeting Title",
  "description": "Meeting description",
  "location": "Meeting location",
  "start": {
    "dateTime": "2023-01-01T10:00:00Z",
    "timeZone": "America/Los_Angeles"
  },
  "end": {
    "dateTime": "2023-01-01T11:00:00Z",
    "timeZone": "America/Los_Angeles"
  },
  "organizer": {
    "email": "organizer@company.com",
    "displayName": "Organizer Name"
  },
  "creator": {
    "email": "creator@company.com",
    "displayName": "Creator Name"
  },
  "attendees": [
    {
      "email": "attendee1@company.com",
      "displayName": "Attendee One",
      "responseStatus": "accepted",
      "optional": false,
      "organizer": false
    }
  ]
}
```

## Real-Time Processing

### Event Filtering

Uses `real_time_event_filter('event_id')` for incremental processing:

- Filters to specific calendar event IDs for real-time updates
- Supports both batch and incremental refreshes
- Tagged with `realtime` for processing orchestration

### Deduplication Strategy

```sql
-- Keep latest occurrence of each calendar event
{{ get_first_or_last_row(
    source='extracted',
    partition_by='calendar_event_id',
    order_by='start_time',
    column_label='is_latest',
    get='last'
) }}
```

## Key Principles

1. **Meeting-Centric Design**: Events represent calendar meetings with
   external/internal classification
2. **Participation Model**: Many-to-many relationships capture all meeting
   participants
3. **Smart Domain Filtering**: Only business domains become groups
4. **Nexus Integration**: Follows framework patterns for automatic inclusion
5. **Real-time Ready**: Supports both batch and incremental processing
6. **Role Distinction**: Clear roles for organizers, creators, and attendees
