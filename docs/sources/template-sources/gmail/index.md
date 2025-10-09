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
extracts entity identifiers for both people and groups, and creates relationship
declarations - all through simple configuration.

## Overview

The Gmail template source transforms raw Gmail message data into the nexus
framework using the v0.3.0 entity-centric architecture:

- **📧 Email Events**: Each message becomes a `message_sent` event
- **👤 Person Entities**: Extracts email addresses from senders and recipients
- **🏢 Group Entities**: Creates groups from non-generic email domains
- **🔗 Relationships**: Links people to their organizations via email domains
  (membership type)
- **🏷️ Entity Traits**: Captures names and email addresses for all entities

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
SELECT * FROM {{ ref('nexus_events') }}
WHERE source = 'gmail'
ORDER BY occurred_at DESC
LIMIT 10;

-- See email participants with entity information
SELECT
    ev.event_description as subject,
    ev.occurred_at,
    e.name,
    e.email,
    ei.role
FROM {{ ref('nexus_events') }} ev
JOIN {{ ref('nexus_entity_identifiers') }} ei ON ev.event_id = ei.event_id
JOIN {{ ref('nexus_entities') }} e ON ei.identifier_value = e.email
WHERE ev.source = 'gmail'
  AND e.entity_type = 'person'
ORDER BY ev.occurred_at DESC
LIMIT 20;
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

Gmail uses the **four-layer source architecture** for optimal DevX and
performance:

### Layer 1: Base - `gmail_messages_base.sql`

Transforms raw Gmail JSON into structured data.

**Key Features:**

- Parses email addresses using `parse_gmail_email()` macro
- Extracts names using `extract_gmail_name()` macro
- Identifies internal vs external participants
- Filters generic email domains
- Creates sender/recipients STRUCTs

### Layer 2: Normalized - `gmail_messages.sql`

Clean, deduplicated messages ready for processing.

### Layer 3: Intermediate - 6 Models

Separate person/group logic for better debugging and transparency:

- `gmail_message_events.sql` - Message events with metadata
- `gmail_message_person_identifiers.sql` - Sender/recipient email identifiers
- `gmail_message_group_identifiers.sql` - Domain identifiers (filtered)
- `gmail_message_person_traits.sql` - Names and emails
- `gmail_message_group_traits.sql` - Domain names
- `gmail_message_relationship_declarations.sql` - Person→domain memberships

### Layer 4: Union - 4 Models (Nexus Integration)

These models feed directly into the nexus pipeline:

#### `gmail_events`

Creates nexus-compatible events:

```sql
event_id               -- Unique event identifier (evt_ prefix)
event_name             -- "message_sent"
occurred_at            -- Email send time
event_description      -- Email subject
event_type             -- "email"
source                 -- "gmail"
```

#### `gmail_entity_identifiers`

Unified person + group identifiers:

```sql
entity_identifier_id   -- Unique identifier (ent_idfr_ prefix)
event_id               -- Reference to email event
edge_id                -- Groups related identifiers
entity_type            -- "person" or "group"
identifier_type        -- "email" or "domain"
identifier_value       -- Email address or domain
role                   -- "sender", "recipient", "sender_domain", "recipient_domain"
occurred_at            -- Email timestamp
source                 -- "gmail"
```

**Role Types:**

- Person roles: `sender`, `recipient`
- Group roles: `sender_domain`, `recipient_domain`

#### `gmail_entity_traits`

Unified person + group traits:

```sql
entity_trait_id        -- Unique trait identifier (ent_tr_ prefix)
event_id               -- Reference to email event
entity_type            -- "person" or "group"
identifier_type        -- "email" or "domain"
identifier_value       -- Email address or domain
trait_name             -- "name", "email", or "name" (for domains)
trait_value            -- The trait value
role                   -- Role in the email
occurred_at            -- Email timestamp
source                 -- "gmail"
```

#### `gmail_relationship_declarations`

Person→group relationship declarations:

```sql
relationship_declaration_id  -- Unique ID (rel_decl_ prefix)
event_id                     -- Reference to email event
occurred_at                  -- Email timestamp
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
source                       -- "gmail"
```

**Filtered Generic Domains:**

- gmail.com, yahoo.com, hotmail.com, outlook.com
- aol.com, icloud.com, me.com, live.com, msn.com
- googlemail.com, ymail.com, rocketmail.com, protonmail.com
- mail.com, zoho.com

## Integration Examples

### Customer Communication Timeline

```sql
-- View all email communication with a specific customer
WITH customer AS (
    SELECT entity_id, email, name
    FROM {{ ref('nexus_entities') }}
    WHERE email = 'customer@client.com'
      AND entity_type = 'person'
)

SELECT
    e.occurred_at,
    e.event_description as subject,
    sender.email as from_email,
    sender.name as from_name,
    customer.email as customer_email
FROM {{ ref('nexus_events') }} e
JOIN {{ ref('nexus_entity_identifiers') }} ei ON e.event_id = ei.event_id
JOIN customer ON ei.identifier_value = customer.email
LEFT JOIN {{ ref('nexus_entities') }} sender
    ON sender.entity_type = 'person'
    AND EXISTS (
        SELECT 1 FROM {{ ref('nexus_entity_identifiers') }} ei2
        WHERE ei2.event_id = e.event_id
          AND ei2.identifier_value = sender.email
          AND ei2.role = 'sender'
    )
WHERE e.source = 'gmail'
ORDER BY e.occurred_at DESC;
```

### Email Domain Analysis

```sql
-- Analyze email communication by domain with relationship data
SELECT
    g.name as domain,
    COUNT(DISTINCT e.event_id) as email_count,
    COUNT(DISTINCT p.entity_id) as unique_people,
    MIN(e.occurred_at) as first_contact,
    MAX(e.occurred_at) as last_contact
FROM {{ ref('nexus_events') }} e
JOIN {{ ref('nexus_entity_identifiers') }} gei
    ON e.event_id = gei.event_id
    AND gei.entity_type = 'group'
JOIN {{ ref('nexus_entities') }} g
    ON gei.identifier_value = g.domain
    AND g.entity_type = 'group'
JOIN {{ ref('nexus_relationships') }} r
    ON r.entity_b_id = g.entity_id
JOIN {{ ref('nexus_entities') }} p
    ON r.entity_a_id = p.entity_id
    AND p.entity_type = 'person'
WHERE e.source = 'gmail'
GROUP BY g.entity_id, g.name
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
