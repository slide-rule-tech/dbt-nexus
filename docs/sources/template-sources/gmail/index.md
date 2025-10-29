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
- **🔄 Cross-Account Deduplication**: Uses `Message-ID` header to deduplicate
  emails across multiple Gmail accounts
- **📨 Participant Roles**: Distinguishes between `sender`, `recipient`, `cced`,
  and `bcced` participants

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

Your Gmail source table must use the **STANDARD_TABLE_SCHEMA** structure:

```sql
CREATE TABLE `project.schema.table` (
  _raw_record JSON NOT NULL,           -- Gmail message as JSON
  _ingested_at TIMESTAMP NOT NULL,      -- When the record was ingested
  _connection_id STRING NOT NULL,       -- Nango connection ID
  _stream_id STRING NOT NULL,           -- Stream identifier (e.g., 'default')
  _sync_timestamp TIMESTAMP,           -- Timestamp-based cursor for incremental sync
  _sync_token STRING                    -- Token-based cursor (history ID)
);
```

### Gmail Message JSON Structure

The `_raw_record` column should contain Gmail API message format:

```json
{
  "id": "message_id_123",
  "threadId": "thread_id_456",
  "internalDate": "1609459200000",
  "headers": [
    {
      "name": "Message-ID",
      "value": "<message-id-abc123@mail.gmail.com>"
    },
    {
      "name": "Subject",
      "value": "Meeting Follow-up"
    },
    {
      "name": "From",
      "value": "John Doe <john@company.com>"
    },
    {
      "name": "To",
      "value": "jane@client.com, bob@partner.com"
    },
    {
      "name": "Cc",
      "value": "team@company.com"
    },
    {
      "name": "Bcc",
      "value": "archive@company.com"
    }
  ],
  "body_text": "Thanks for the great meeting..."
}
```

**Key Fields:**

- `id`: Gmail-specific message ID (unique within a single account)
- `threadId`: Thread identifier
- `internalDate`: Unix timestamp in milliseconds
- `headers`: Array of header objects (must include `Message-ID` for
  deduplication)
- `body_text`: Plain text body content

## Generated Models

Gmail uses the **four-layer source architecture** with split normalized models
for optimal performance:

### Layer 1: Base - `gmail_messages_base.sql`

Simple passthrough with zero transformation overhead:

**Key Features:**

- Direct `SELECT *` from source table
- No JSON parsing or transformations
- Minimal overhead for maximum performance

### Layer 2: Normalized - Split Structure

#### `gmail_messages.sql` - Message-Level Data

Clean, deduplicated email messages.

**Key Features:**

- **Cross-Account Deduplication**: Uses `Message-ID` header as primary
  identifier
- **Header Extraction**: Extracts `Message-ID` and `Subject` from headers array
- **Timestamp Conversion**: Converts `internalDate` (milliseconds) to `sent_at`
  timestamp
- **Thread Support**: Preserves `threadId` for conversation threading
- **Body Content**: Extracts `body_text` and `attachments` array

**Contains:**

```sql
message_id               -- Primary key from Message-ID header
thread_id                -- Thread identifier
gmail_message_id         -- Gmail-specific ID (from $.id)
message_id_header        -- Message-ID header value
sent_at                  -- Parsed timestamp from internalDate
subject                  -- Email subject
body                     -- Email body text
attachments_array        -- Array of attachment objects
_ingested_at             -- Ingestion timestamp
raw_record               -- Full JSON record
_connection_id           -- Nango connection ID
_stream_id               -- Stream identifier
_sync_timestamp          -- Sync timestamp
_sync_token              -- Sync token (history ID)
source                   -- "gmail"
```

**Deduplication Logic:**

- Uses `Message-ID` header value as primary `message_id`
- Deduplicates across accounts:
  `QUALIFY row_number() OVER (PARTITION BY message_id ORDER BY sent_at DESC) = 1`
- Only processes messages with valid `Message-ID` header

**Why Message-ID instead of Gmail ID?**

Gmail message IDs (`$.id`) are unique within a single account, but the same
email appears with different IDs across different accounts. `Message-ID` is a
standard email header that's stable across accounts, making it perfect for
cross-account deduplication.

#### `gmail_message_participants.sql` - Participant-Level Data

One row per participant per message, normalized and validated.

**Key Features:**

- Extracts all participants from headers: `From`, `To`, `Cc`, `Bcc`
- Uses Gmail email parsing macros for consistency
- Normalizes email addresses using `validate_and_normalize_email()`
- Extracts domains for group entity creation
- Preserves participant roles: `sender`, `recipient`, `cced`, `bcced`

**Contains:**

```sql
message_id               -- Message-ID header (matches gmail_messages)
name                     -- Participant name (extracted or from header)
email                    -- Normalized email address
domain                   -- Extracted domain
role                     -- "sender", "recipient", "cced", or "bcced"
sent_at                  -- Message send time
_ingested_at             -- Ingestion timestamp
```

**Role Types:**

- `sender`: Person who sent the email (from `From` header)
- `recipient`: Person in `To` field
- `cced`: Person in `Cc` field
- `bcced`: Person in `Bcc` field

**Participant Extraction Pattern:**

1. Extract `From` header → single sender
2. Split `To` header by comma → multiple recipients
3. Split `Cc` header by comma → multiple CC recipients
4. Split `Bcc` header by comma → multiple BCC recipients
5. Parse each email using `parse_gmail_email()` macro
6. Extract name using `extract_gmail_name()` macro
7. Validate and normalize using `validate_and_normalize_email()` macro

### Layer 3: Intermediate - 6 Models

Separate person/group logic for better debugging and transparency:

- `gmail_message_events.sql` - Message events with metadata (reads from
  `gmail_messages`)
- `gmail_message_person_identifiers.sql` - Sender/recipient email identifiers
  (reads from `gmail_message_participants`)
- `gmail_message_group_identifiers.sql` - Domain identifiers filtered (reads
  from `gmail_message_participants`)
- `gmail_message_person_traits.sql` - Names and emails (reads from
  `gmail_message_participants`)
- `gmail_message_group_traits.sql` - Domain names (reads from
  `gmail_message_participants`)
- `gmail_message_relationship_declarations.sql` - Person→domain memberships
  (reads from `gmail_message_participants`)

**Key Pattern:** All intermediate models read directly from normalized tables
without joins. Person/group models read from `gmail_message_participants`, event
model reads from `gmail_messages`.

### Layer 4: Union - 4 Models (Nexus Integration)

These models feed directly into the nexus pipeline:

#### `gmail_events`

Creates nexus-compatible events:

```sql
event_id               -- Unique event identifier (evt_ prefix)
event_name             -- "message_sent"
occurred_at            -- Email send time (sent_at)
event_description      -- Email subject
event_type             -- "email"
source                 -- "gmail"
_ingested_at           -- Ingestion timestamp
message_id             -- Message-ID header
thread_id              -- Thread identifier
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
role                   -- Participation role (see below)
occurred_at            -- Email timestamp
source                 -- "gmail"
_ingested_at           -- Ingestion timestamp
```

**Role Types:**

- Person roles: `sender`, `recipient`, `cced`, `bcced`
- Group roles: `sender`, `recipient`, `cced`, `bcced` (for domain tracking)

#### `gmail_entity_traits`

Unified person + group traits:

```sql
entity_trait_id        -- Unique trait identifier (ent_tr_ prefix)
event_id               -- Reference to email event
entity_type            -- "person" or "group"
identifier_type        -- "email" or "domain"
identifier_value       -- Email address or domain
trait_name             -- "name", "email" (for persons) or "domain_name" (for domains)
trait_value            -- The trait value
occurred_at            -- Email timestamp
source                 -- "gmail"
_ingested_at           -- Ingestion timestamp
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
entity_a_role                -- "sender", "recipient", "cced", or "bcced"
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

## Cross-Account Deduplication

Gmail uses the `Message-ID` header for cross-account deduplication:

### Message-ID Header

- **Primary Key**: `Message-ID` header value from email headers
- **Deduplication**: Messages with the same `Message-ID` across different Gmail
  accounts are treated as the same email
- **Use Case**: Same email appearing in sender's and all recipients' inboxes

### Deduplication Logic

```sql
-- Extract Message-ID header
message_id_header = (
  SELECT JSON_EXTRACT_SCALAR(header, '$.value')
  FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
  WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'message-id'
  LIMIT 1
)

-- Use Message-ID as primary identifier
-- Deduplicate keeping latest by sent_at
QUALIFY row_number() OVER (
  PARTITION BY message_id
  ORDER BY sent_at DESC
) = 1
```

This ensures the same email (identified by `Message-ID`) appearing in multiple
Gmail accounts is only counted once, while preserving all participant
information from each account's perspective.

### Why Not Gmail Message ID?

Gmail message IDs (`$.id`) are account-specific. The same email has different
IDs when it appears in:

- Sender's Sent folder
- Recipient's Inbox
- CC recipient's Inbox

`Message-ID` is standardized by RFC 2822 and is consistent across all accounts,
making it the perfect deduplication key.

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
    customer.email as customer_email,
    ei.role as customer_role
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
    COUNT(DISTINCT CASE WHEN ei.role = 'sender' THEN p.entity_id END) as senders,
    COUNT(DISTINCT CASE WHEN ei.role = 'recipient' THEN p.entity_id END) as recipients,
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
JOIN {{ ref('nexus_entity_identifiers') }} ei
    ON ei.event_id = e.event_id
    AND ei.identifier_value = p.email
WHERE e.source = 'gmail'
GROUP BY g.entity_id, g.name
ORDER BY email_count DESC;
```

### Participant Role Analysis

```sql
-- Analyze email participation patterns by role
SELECT
    role,
    COUNT(DISTINCT message_id) as message_count,
    COUNT(DISTINCT email) as unique_participants,
    COUNT(*) as total_participations
FROM {{ ref('gmail_message_participants') }}
WHERE sent_at >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY role
ORDER BY total_participations DESC;
```

### Thread Conversation Analysis

```sql
-- Analyze email threads with participant counts
SELECT
    thread_id,
    COUNT(DISTINCT message_id) as message_count,
    COUNT(DISTINCT email) as unique_participants,
    ARRAY_AGG(DISTINCT subject ORDER BY sent_at LIMIT 1)[OFFSET(0)] as thread_subject,
    MIN(sent_at) as thread_start,
    MAX(sent_at) as thread_end
FROM {{ ref('gmail_message_participants') }} p
JOIN {{ ref('gmail_messages') }} m ON p.message_id = m.message_id
WHERE sent_at >= CURRENT_DATE - INTERVAL 90 DAY
GROUP BY thread_id
HAVING message_count > 1
ORDER BY thread_start DESC;
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
        +unique_key: message_id
        +cluster_by: ["sent_at"]
```

### Partitioning (BigQuery)

Optimize time-based queries:

```yaml
models:
  nexus:
    sources:
      gmail:
        +partition_by:
          { "field": "sent_at", "data_type": "timestamp", "granularity": "day" }
```

## Troubleshooting

### Common Issues

**1. No Gmail events appearing**

- Check `nexus.gmail.enabled: true` is set
- Verify source table exists with STANDARD_TABLE_SCHEMA structure
- Ensure `Message-ID` header is present in raw JSON records
- Verify source data has the expected JSON structure

**2. Missing email participants**

- Check that `From`, `To`, `Cc`, `Bcc` headers are not null/empty in source data
- Verify email parsing macros are working correctly
- Ensure participant normalization is enabled

**3. Generic domains appearing as groups**

- Review the generic domain filter list
- Add additional generic domains if needed
- Verify `filter_non_generic_domains()` macro is working

**4. Duplicate emails across accounts**

- Verify `Message-ID` header is being extracted correctly
- Check that deduplication QUALIFY clause is working
- Ensure all messages have valid `Message-ID` headers

### Debugging Queries

```sql
-- Check raw source data
SELECT
    _raw_record,
    _ingested_at,
    _connection_id,
    _stream_id
FROM {{ source('gmail', 'messages') }}
LIMIT 5;

-- Verify base model processing
SELECT * FROM {{ ref('gmail_messages_base') }}
LIMIT 10;

-- Check normalized messages with deduplication
SELECT
    message_id,
    gmail_message_id,
    subject,
    sent_at,
    thread_id
FROM {{ ref('gmail_messages') }}
ORDER BY sent_at DESC
LIMIT 10;

-- Verify participants extraction
SELECT
    message_id,
    email,
    role,
    domain
FROM {{ ref('gmail_message_participants') }}
LIMIT 20;

-- Check Message-ID extraction
SELECT
    message_id,
    gmail_message_id,
    message_id_header,
    COUNT(*) as count
FROM {{ ref('gmail_messages') }}
GROUP BY message_id, gmail_message_id, message_id_header
HAVING count > 1;
```

## Advanced Configuration

### Custom Email Filtering

Filter specific messages or domains:

```sql
-- Filter to external emails only
SELECT * FROM {{ ref('gmail_messages') }} m
WHERE EXISTS (
    SELECT 1 FROM {{ ref('gmail_message_participants') }} p
    WHERE p.message_id = m.message_id
      AND p.domain NOT IN ('yourcompany.com')
);
```

### Header Extraction

Add custom header extraction:

```sql
-- Extract custom headers in normalized model
(SELECT JSON_EXTRACT_SCALAR(header, '$.value')
 FROM UNNEST(JSON_EXTRACT_ARRAY(_raw_record, '$.headers')) as header
 WHERE LOWER(JSON_EXTRACT_SCALAR(header, '$.name')) = 'custom-header'
 LIMIT 1) as custom_header_value
```

## Migration Guide

### From Custom Gmail Models

If you have existing custom Gmail models:

1. **Backup Current Models**: Save your existing logic
2. **Compare Schemas**: Ensure data compatibility with STANDARD_TABLE_SCHEMA
3. **Verify Message-ID**: Ensure your source data includes `Message-ID` in
   headers
4. **Enable Template Source**: Configure to point to your data
5. **Test Output**: Verify data quality, deduplication, and completeness
6. **Update References**: Change refs to use template models
7. **Remove Custom Models**: Clean up old source models

### Schema Compatibility

Ensure your Gmail data includes:

- Message `id` and `threadId`
- `internalDate` for timestamp
- `headers` array with at least `Message-ID`, `From`, `To` headers
- `body_text` for email content
- Optional: `Cc`, `Bcc` headers for participant extraction

### STANDARD_TABLE_SCHEMA Migration

If migrating from old schema with `record` and `synced_at`:

```sql
-- Example migration query
CREATE OR REPLACE TABLE `new_table` AS
SELECT
    old_record as _raw_record,
    synced_at as _ingested_at,
    'connection_123' as _connection_id,
    'default' as _stream_id,
    synced_at as _sync_timestamp,
    NULL as _sync_token
FROM `old_table`;
```

### Handling Missing Message-ID

If some messages lack `Message-ID` headers:

```sql
-- Option 1: Use Gmail ID as fallback
COALESCE(
    message_id_header,
    CONCAT('gmail_', gmail_message_id)
) as message_id

-- Option 2: Filter out messages without Message-ID
WHERE message_id_header IS NOT NULL
```

---

**Ready to integrate Gmail?** Set `nexus.gmail.enabled: true` and run
`dbt build`!
