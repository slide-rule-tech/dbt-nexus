# Gmail Source Documentation

This document describes the Gmail source integration for the CRM warehouse,
which processes email messages from Gmail via Nango integration into events,
person/group identifiers, traits, and event participation relationships.

## Overview

The Gmail source follows the established nexus framework patterns but includes
unique email-specific processing:

- Raw data comes from BigQuery `sliderule-analytics.gmail.messages` table with
  JSON records
- Base model transforms Gmail API responses into structured events
- Each email becomes a single `message_sent` event with multiple participants
- Email addresses are parsed for person identifiers and domain extraction for
  groups
- Generic email domains (gmail.com, etc.) are filtered out from group creation
- Event participation creates many-to-many relationships between persons and
  email events

## Architecture

```
Gmail Messages (JSON) → Base Model → Events + Identifiers + Traits + Memberships
                                 ↓
                           Nexus Framework → Final Tables
```

### Data Flow

1. **Nango Sync**: `google-mail` integration syncs Gmail messages to BigQuery
2. **Base Processing**: `gmail_messages_base.sql` transforms JSON to structured
   data
3. **Event Creation**: Each message = 1 `message_sent` event
4. **Participant Extraction**: Sender + recipients become event participants
5. **Identity Resolution**: Email addresses → person identifiers, domains →
   group identifiers
6. **Final Integration**: Auto-included in nexus `events`, `persons`, `groups`
   tables

## File Structure

```
sources/gmail/
├── gmail.yml                           # Source definition
├── base/
│   └── gmail_messages_base.sql         # JSON transformation & deduplication
├── gmail_events.sql                    # Event model
├── gmail_person_identifiers.sql       # Email extraction for persons
├── gmail_group_identifiers.sql        # Domain extraction for groups
├── gmail_person_traits.sql            # Person email traits
├── gmail_group_traits.sql             # Group domain traits
├── gmail_membership_identifiers.sql   # Event participation (sender/recipients)
└── GMAIL_SOURCE.md                     # This documentation
```

## Key Models

### Base Model (`gmail_messages_base.sql`)

Transforms raw Gmail JSON into structured fields:

```sql
-- Extracts message_id from JSON first (no direct ID column)
-- Applies real-time filtering on message_id
-- Generates event_id from message_id
-- Parses timestamp, sender, recipients, subject, body
-- Deduplicates on message_id (latest occurrence)
-- Adds source = 'gmail' and event_description
```

**Key Fields:**

- `event_id`: Generated surrogate key from message_id
- `message_id`: Gmail message ID from JSON
- `sender`: Email address of sender
- `recipients`: Comma-separated string of recipient emails
- `subject`, `body`: Message content
- `thread_id`: Gmail conversation thread ID

### Events Model (`gmail_events.sql`)

Creates standardized events from messages:

```sql
-- event_name: 'message_sent'
-- event_type: 'email'
-- event_value: message_id
-- value_unit: 'message'
-- source: 'gmail'
-- source_table: 'gmail_messages'
```

### Person Identifiers (`gmail_person_identifiers.sql`)

Extracts email addresses as person identifiers:

```sql
-- Sender: Uses nexus.unpivot_identifiers macro
-- Recipients: Manual parsing of comma-separated string
-- identifier_type: 'email' for all
-- Creates one identifier per email address
```

**Processing:**

1. **Sender**: Direct extraction via nexus macro
2. **Recipients**: `SPLIT(recipients, ',')` + `UNNEST` + `TRIM`
3. **Union**: Combines sender + all recipients

### Group Identifiers (`gmail_group_identifiers.sql`)

Extracts non-generic domains as group identifiers:

```sql
-- Regex extraction: REGEXP_EXTRACT(email, r'@(.+)')
-- Generic domain filtering (gmail.com, yahoo.com, etc.)
-- identifier_type: 'domain'
-- Only creates groups for business domains
```

**Generic Domains Excluded:**

- gmail.com, yahoo.com, hotmail.com, outlook.com
- aol.com, icloud.com, me.com, live.com, msn.com
- googlemail.com, ymail.com, rocketmail.com
- protonmail.com, mail.com, zoho.com

### Person Traits (`gmail_person_traits.sql`)

Maps email addresses to person traits:

```sql
-- Sender: Uses nexus.unpivot_traits macro
-- Recipients: Manual trait creation
-- trait_name: 'email'
-- trait_value: email address
-- Creates email trait for each participant
```

### Group Traits (`gmail_group_traits.sql`)

Maps domains to group traits:

```sql
-- domain trait: Maps domain to itself
-- type trait: All domains get type = 'organization'
-- Only non-generic domains included
```

### Event Participation (`gmail_membership_identifiers.sql`)

Creates many-to-many relationships between persons and email events:

```sql
-- Sender: role = 'sender'
-- Recipients: role = 'recipient'
-- Links person_identifier (email) to event_id
-- Enables "show all emails this person participated in"
```

## Email Processing Logic

### Recipient Parsing

Gmail provides recipients as a comma-separated string. The models handle this
by:

```sql
-- Split and unnest recipients
SELECT event_id, TRIM(recipient_email) as recipient_email
FROM gmail_messages_base,
UNNEST(SPLIT(recipients, ',')) as recipient_email
WHERE recipients IS NOT NULL AND TRIM(recipient_email) != ''
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

- 1 email = 1 `message_sent` event
- Sender + all recipients linked via `membership_identifiers`
- Same event appears for all involved parties
- Roles distinguish participation type (`sender` vs `recipient`)

## Integration with Nexus Framework

### Sources Configuration (`dbt_project.yml`)

```yaml
sources:
  - name: gmail
    events: true # Include in nexus_events
    groups: true # Include in group resolution
    persons: true # Include in person resolution
    memberships: true # Include in membership tracking
```

### Auto-Inclusion

Gmail models are automatically included in:

- `nexus_events`: All `message_sent` events
- `nexus_person_identifiers`: All email addresses
- `nexus_group_identifiers`: All non-generic domains
- `nexus_membership_identifiers`: All event participation

## Nango Integration

### Sync Configuration (`syncAllSourceJob.ts`)

```typescript
{
  connectionId: process.env.GADGET_NANGO_GMAIL_CONNECTION_ID,
  providerConfigKey: "google-mail",
  listAll: false, // 3-day backfill only
  model: "GmailEmail",
  datasetId: "gmail",
  tableId: "messages"
}
```

### Expected JSON Structure

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

## GraphQL Integration

### Event Details Type

```graphql
type GmailMessageEventDetails {
  eventId: ID!
  messageId: String
  threadId: String
  sender: String
  recipients: String
  subject: String
  body: String
}
```

### Resolver Logic

```typescript
// In eventResolvers.ts
if (parent.source === "gmail" && parent.event_type === "email") {
  const details = await dataSources.bigquery.getGmailEventDetails(
    parent.event_id
  );
  return { __typename: "GmailMessageEventDetails", ...details };
}
```

### Query Examples

```graphql
# Get Gmail events with details
{
  events(filters: { sources: ["gmail"] }) {
    events {
      event_name
      occurred_at
      details {
        ... on GmailMessageEventDetails {
          sender
          recipients
          subject
        }
      }
    }
  }
}

# Find person by email and their email events
{
  personByEmail(email: "john@company.com") {
    events(filters: { sources: ["gmail"] }) {
      events {
        event_name
        occurred_at
        event_description
      }
    }
  }
}
```

## Real-Time Processing

### Event Filtering

Uses `real_time_event_filter('message_id')` for incremental processing:

- Filters to specific message IDs for real-time updates
- Supports both batch and incremental refreshes
- Tagged with `realtime` for processing orchestration

### Deduplication Strategy

```sql
-- Keep latest occurrence of each message
{{ get_first_or_last_row(
    source='extracted',
    partition_by='message_id',
    order_by='occurred_at',
    get='last'
) }}
```

## Maintenance & Extension

### Adding New Email Fields

1. Update `gmail_messages_base.sql` to extract new JSON fields
2. Add to person/group traits if relevant for identity resolution
3. Update GraphQL schema if needed for event details

### Modifying Generic Domain List

Update the `generic_domains` CTE in both:

- `gmail_group_identifiers.sql`
- `gmail_group_traits.sql`

### Performance Considerations

- Base model materialized as table for performance
- Deduplication happens early in pipeline
- Domain filtering reduces unnecessary group creation
- Real-time filtering enables incremental processing

## Testing

### Verify Data Flow

```sql
-- Check message processing
SELECT COUNT(*) FROM gmail_messages_base;

-- Check event creation
SELECT COUNT(*) FROM gmail_events;

-- Check person extraction
SELECT COUNT(DISTINCT identifier_value) FROM gmail_person_identifiers;

-- Check domain filtering
SELECT COUNT(DISTINCT identifier_value) FROM gmail_group_identifiers;

-- Check participation
SELECT COUNT(*) FROM gmail_membership_identifiers;
```

### Common Issues

1. **Timestamp Parsing**: Ensure Gmail date format matches `PARSE_TIMESTAMP`
   pattern
2. **Recipient Splitting**: Handle edge cases in comma-separated recipient lists
3. **Domain Extraction**: Regex must handle various email formats
4. **Type Consistency**: Ensure all CTEs have matching column types for UNION
   ALL

## Key Principles

1. **Email-Centric Design**: Events represent email messages, not individual
   recipients
2. **Participation Model**: Many-to-many relationships capture all email
   participants
3. **Smart Domain Filtering**: Only business domains become groups
4. **Nexus Integration**: Follows framework patterns for automatic inclusion
5. **Real-time Ready**: Supports both batch and incremental processing
6. **Type Safety**: Explicit casts prevent UNION ALL type mismatches
