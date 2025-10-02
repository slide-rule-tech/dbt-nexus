---
title: Gmail Template Source
tags: [template-sources, gmail, email, configuration]
summary:
  Ready-to-use Gmail integration for email events, person identifiers, and group
  relationships
---

# Gmail Template Source

The **Gmail Template Source** provides instant integration with Gmail data
through the Nango ETL pipeline. It processes email messages into events,
extracts person and group identifiers, and creates participation relationships -
all through simple configuration.

## Overview

The Gmail template source transforms raw Gmail message data into the nexus
framework:

- **📧 Email Events**: Each message becomes a `message_sent` event
- **👤 Person Identifiers**: Extracts email addresses from senders and
  recipients
- **🏢 Group Identifiers**: Creates groups from non-generic email domains
- **🔗 Memberships**: Links people to their organizations via email domains
- **🏷️ Traits**: Captures names and email addresses as person traits

## Quick Start

### 1. Enable the Template Source

```yaml
# dbt_project.yml
vars:
  nexus:
    gmail:
      enabled: true
```

### 2. Run the Models

```bash
dbt run --select package:nexus
```

### 3. Explore Your Data

```sql
-- View recent Gmail events
SELECT * FROM nexus_events
WHERE source = 'gmail'
ORDER BY occurred_at DESC
LIMIT 10;

-- See email participants
SELECT
    e.event_description as subject,
    e.occurred_at,
    p.name,
    p.email,
    pp.role
FROM nexus_events e
JOIN nexus_person_participants pp ON e.id = pp.event_id
JOIN nexus_persons p ON pp.person_id = p.id
WHERE e.source = 'gmail'
ORDER BY e.occurred_at DESC;
```

## Configuration

### Basic Configuration

```yaml
# dbt_project.yml
vars:
  nexus:
    gmail:
      enabled: true
      # Uses defaults: schema=gmail, table=messages
```

### Custom Source Location

```yaml
vars:
  nexus:
    gmail:
      enabled: true
      location:
        schema: my_email_data
        table: gmail_messages
```

### Required Global Variables

```yaml
vars:
  # Required: Define internal email domains
  internal_domains:
    - "yourcompany.com"
    - "subsidiary.com"

  # Optional: Test email addresses
  test_emails:
    - "test@yourcompany.com"
```

## Data Requirements

### Source Table Schema

Your Gmail source table must have this structure:

```sql
CREATE TABLE `project.schema.table` (
  record JSON,           -- Gmail message as JSON
  synced_at TIMESTAMP    -- When the record was synced
);
```

### Gmail Message JSON Structure

The `record` column should contain Gmail API message format:

```json
{
  "id": "message_id_123",
  "threadId": "thread_id_456",
  "date": "2024-01-15T10:30:00Z",
  "sender": "John Doe <john@company.com>",
  "recipients": "jane@client.com, bob@partner.com",
  "subject": "Meeting Follow-up",
  "body": "Thanks for the great meeting..."
}
```

## Generated Models

### Base Model: `gmail_messages_base`

Transforms raw Gmail JSON into structured data:

**Key Features:**

- Parses email addresses using `parse_gmail_email()` macro
- Extracts names using `extract_gmail_name()` macro
- Identifies internal vs external participants
- Filters generic email domains (gmail.com, yahoo.com, etc.)
- Deduplicates messages by latest timestamp

**Output Schema:**

```sql
event_id               -- Unique identifier for nexus processing
message_id             -- Original Gmail message ID
thread_id              -- Gmail thread ID
subject                -- Email subject line
body                   -- Email body content
sender                 -- STRUCT with email, name, domain, flags
recipients             -- ARRAY of recipient STRUCTs
occurred_at            -- When email was sent
source                 -- "gmail"
```

### Events: `gmail_events`

Creates nexus-compatible events:

```sql
event_id               -- Reference to base model
event_name             -- "message_sent"
occurred_at            -- Email send time
event_description      -- Email subject
event_type             -- "email"
source                 -- "gmail"
```

### Person Identifiers: `gmail_person_identifiers`

Extracts email addresses from senders and recipients with role context:

**Role Types:**

- `sender` - Person who sent the email
- `recipient` - Person who received the email

```sql
event_id               -- Reference to email event
edge_id                 -- Groups related identifiers
identifier_type        -- "email"
identifier_value       -- Email address
role                   -- "sender" or "recipient"
occurred_at            -- Email timestamp
source                 -- "gmail"
```

### Person Traits: `gmail_person_traits`

Captures person information:

**Trait Types:**

- `email` - Email address
- `full_name` - Display name from email

```sql
event_id               -- Reference to email event
edge_id                 -- Groups related traits
trait_name             -- "email" or "full_name"
trait_value            -- The trait value
occurred_at            -- Email timestamp
source                 -- "gmail"
```

### Group Identifiers: `gmail_group_identifiers`

Creates groups from email domains (excludes generic providers):

**Filtered Domains:**

- gmail.com, yahoo.com, hotmail.com, outlook.com
- aol.com, icloud.com, me.com, live.com, msn.com
- googlemail.com, ymail.com, rocketmail.com, protonmail.com
- mail.com, zoho.com

```sql
event_id               -- Reference to email event
edge_id                 -- Groups related identifiers
identifier_type        -- "domain"
identifier_value       -- Email domain
occurred_at            -- Email timestamp
source                 -- "gmail"
```

### Group Traits: `gmail_group_traits`

Domain information for organizations:

```sql
event_id               -- Reference to email event
edge_id                 -- Groups related traits
trait_name             -- "domain"
trait_value            -- Domain name
occurred_at            -- Email timestamp
source                 -- "gmail"
```

### Membership Identifiers: `gmail_membership_identifiers`

Links people to organizations via email domains:

```sql
event_id               -- Reference to email event
occurred_at            -- Email timestamp
person_identifier      -- Email address
person_identifier_type -- "email"
group_identifier       -- Email domain
group_identifier_type  -- "domain"
role                   -- "sender" or "recipient"
source                 -- "gmail"
```

## Integration Examples

### Customer Communication Timeline

```sql
-- View all email communication with a customer
WITH customer_emails AS (
    SELECT DISTINCT person_id
    FROM nexus_resolved_person_identifiers
    WHERE identifier_value = 'customer@client.com'
)

SELECT
    e.occurred_at,
    e.event_description as subject,
    sender.email as from_email,
    recipients.email as to_email
FROM nexus_events e
JOIN nexus_person_participants pp ON e.id = pp.event_id
JOIN customer_emails c ON pp.person_id = c.person_id
JOIN nexus_resolved_person_identifiers sender ON sender.person_id = pp.person_id
JOIN nexus_resolved_person_identifiers recipients ON recipients.person_id != pp.person_id
WHERE e.source = 'gmail'
ORDER BY e.occurred_at DESC;
```

### Email Domain Analysis

```sql
-- Analyze email communication by domain
SELECT
    g.domain,
    COUNT(DISTINCT e.id) as email_count,
    COUNT(DISTINCT p.id) as unique_people,
    MIN(e.occurred_at) as first_contact,
    MAX(e.occurred_at) as last_contact
FROM nexus_events e
JOIN nexus_group_participants gp ON e.id = gp.event_id
JOIN nexus_groups g ON gp.group_id = g.id
JOIN nexus_person_participants pp ON e.id = pp.event_id
JOIN nexus_persons p ON pp.person_id = p.id
WHERE e.source = 'gmail'
GROUP BY g.domain
ORDER BY email_count DESC;
```

## Performance Considerations

### Incremental Processing

For large Gmail datasets:

```yaml
# dbt_project.yml
models:
  nexus:
    sources:
      gmail:
        +materialized: incremental
        +unique_key: event_id
        +cluster_by: ["occurred_at"]
```

### Filtering

Use real-time event filtering for specific messages:

```yaml
# dbt_project.yml
vars:
  realtime_event_id: ["msg_123", "msg_456"] # Process specific messages
```

## Troubleshooting

### Common Issues

**1. No Gmail events appearing**

- Check `nexus.gmail.enabled: true` is set
- Verify source table exists and has data
- Ensure `internal_domains` is configured

**2. Missing email participants**

- Check that sender/recipient emails are not null in source data
- Verify email parsing macros are working correctly

**3. Generic domains appearing as groups**

- Review the generic domain filter list
- Add additional generic domains if needed

### Debugging Queries

```sql
-- Check raw source data
SELECT * FROM {{ nexus_source('gmail', 'messages') }} LIMIT 5;

-- Verify base model processing
SELECT * FROM {{ ref('gmail_messages_base') }} LIMIT 5;

-- Check email parsing
SELECT
    sender_raw,
    sender.email as parsed_email,
    sender.name as parsed_name
FROM {{ ref('gmail_messages_base') }}
LIMIT 10;
```

## Migration from Custom Gmail Models

### 1. **Compare Data Structure**

Ensure your Gmail data matches the expected JSON format

### 2. **Configure Template Source**

Point the template source to your existing data

### 3. **Test Processing**

Run the template source and verify output quality

### 4. **Update Dependencies**

Update any models that referenced your custom Gmail models

### 5. **Remove Custom Models**

Delete your custom Gmail source models

## Next Steps

- **[Google Calendar Template Source](../google_calendar/)** - Add calendar data
- **[Custom Source Creation](../../how-to/custom-sources.md)** - Build your own
  sources
- **[Advanced Configuration](../../reference/configuration.md)** - Fine-tune
  settings
- **[Performance Optimization](../../explanations/performance.md)** - Scale to
  production

---

**Ready to integrate Gmail?** Set `nexus.gmail.enabled: true` and run
`dbt build`!
