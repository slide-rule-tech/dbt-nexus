# Entities and Relationships Architecture (Rewrite)

## Overview

This document describes the new, unified, entity‑centric architecture for
dbt‑nexus. In this design, all business objects are modeled as entities, and any
entity can have explicit relationships with any other entity. Identity (entity)
resolution unifies identifiers and traits across disparate systems.

## Core Insight

- Entities have relationships with each other.
- Entity resolution (identity resolution) normalizes data across systems to a
  single `entity_id` per real‑world entity.

This eliminates artificial boundaries between `persons` and `groups`, simplifies
modeling, and enables new entity types (e.g., `task`, `contract`, `product`,
`location`).

## Architecture Principles

1. Entity‑centric: one `entities` table for all types
2. Universal relationships: one `relationships` table for all pairs
3. Deterministic: relationships are declared by sources (not inferred)
4. Source‑agnostic: works for CRM, HR, ticketing, commerce, etc.
5. Layered, incremental, temporal: same nexus guarantees

## Data Flow

```mermaid
graph TD
  A[Raw Data Layer] --> B[Source Event Log]
  B --> C[Core Event Log]
  C --> D[Identity (Entity) Resolution]
  D --> E[Final Tables]

  subgraph Entities
    B1[Source Entity Identifiers/Traits]
    C1[Entity Identifiers/Traits]
    D1[Resolved Entity Identifiers/Traits]
    E1[Entities]
  end

  subgraph Relationships
    B2[Source Relationship Declarations]
    C2[Relationship Declarations]
    D2[Resolved Relationship Declarations]
    E2[Relationships]
  end

  B1 --> C1 --> D1 --> E1
  B2 --> C2 --> D2 --> E2
```

## Schemas

### Entities (Final)

```sql
-- entities
{
  entity_id: STRING,
  entity_type: STRING,          -- person | group | task | contract | product | location | event_series
  name: STRING,
  is_active: BOOLEAN,

  -- Common/optional
  email: STRING,
  phone: STRING,
  domain: STRING,
  internal: BOOLEAN,

  -- Person
  title: STRING,
  timezone: STRING,

  -- Group
  company_size: STRING,
  industry: STRING,

  -- Task
  task_status: STRING,
  task_priority: STRING,
  task_due_date: DATE,

  -- Contract
  contract_value: NUMERIC,
  contract_start_date: DATE,
  contract_end_date: DATE,

  -- Location
  address: STRING,
  city: STRING,
  state: STRING,
  country: STRING,

  -- Product
  product_category: STRING,
  product_version: STRING,

  -- Metadata
  first_seen_at: TIMESTAMP,
  last_updated_at: TIMESTAMP,
  primary_source: STRING
}
```

### Relationships (Final)

```sql
-- relationships
{
  relationship_id: STRING,
  entity_a_id: STRING,
  entity_a_type: STRING,
  entity_a_role: STRING,
  entity_b_id: STRING,
  entity_b_type: STRING,
  entity_b_role: STRING,
  relationship_type: STRING,      -- advisor_client | manager_employee | franchisee_location | agency_client | assignee_task | customer_contract | ...
  relationship_direction: STRING, -- bidirectional | a_to_b | b_to_a
  is_primary: BOOLEAN,
  is_active: BOOLEAN,

  -- Event-based scoring (optional)
  interaction_score: FLOAT,
  email_interactions: INTEGER,
  meeting_interactions: INTEGER,
  total_interactions: INTEGER,
  first_interaction_at: TIMESTAMP,
  last_interaction_at: TIMESTAMP,

  -- Lifecycle
  established_at: TIMESTAMP,
  last_updated_at: TIMESTAMP,
  primary_source: STRING,
  _last_calculated: TIMESTAMP
}
```

## Naming Conventions

- Entity types (singular): `person`, `group`, `task`, `contract`, `product`,
  `location`, `event_series`
- Relationship types: `{role_a}_{role_b}` (e.g., `advisor_client`,
  `assignee_task`, `agency_client`)
- Pre‑resolution models use the term: `relationship_declarations`

Model names by layer:

- L2 Source: `source_entity_identifiers`, `source_entity_traits`,
  `source_relationship_declarations`
- L3 Core: `entity_identifiers`, `entity_traits`, `relationship_declarations`
- L4 Resolution: `resolved_entity_identifiers`, `resolved_entity_traits`,
  `resolved_relationship_declarations`
- L5 Final: `entities`, `relationships`

## Migration Plan (Rewrite)

This is a full rewrite. dbt rebuilds models on run, so no stateful DB migration
is required.

### Model Consolidation (cuts model count ~50%)

Before (Gmail example):

```
sources/gmail/
  gmail_person_identifiers.sql
  gmail_person_traits.sql
  gmail_group_identifiers.sql
  gmail_group_traits.sql
  gmail_membership_identifiers.sql
  gmail_events.sql
```

After:

```
sources/gmail/
  gmail_entity_identifiers.sql
  gmail_entity_traits.sql
  gmail_relationship_declarations.sql
  gmail_events.sql
```

Core/Resolution/Final similarly consolidate from person+group to entity‑level
models and from membership to universal relationships.

### Breaking Changes

- Removed final `persons`, `groups`, `memberships` in favor of `entities`,
  `relationships`
- Renamed fields: `person_id`/`group_id` → `entity_id`;
  `membership_identifier_id` → `relationship_declaration_id`
- Added required fields: `entity_type`, `entity_a_type`, `entity_b_type`,
  `relationship_direction`

### Source Transform Examples

Gmail entity identifiers (new):

```sql
-- gmail_entity_identifiers.sql
WITH person_identifiers AS (
  SELECT
    {{ create_nexus_id('entity_identifier', ['event_id', 'sender.email', "'person'", 'occurred_at']) }} as id,
    event_id,
    'email' as identifier_type,
    sender.email as identifier_value,
    'person' as entity_type,
    'gmail' as source,
    occurred_at
  FROM {{ ref('gmail_messages_base') }}
  WHERE sender.email IS NOT NULL
),

group_identifiers AS (
  SELECT
    {{ create_nexus_id('entity_identifier', ['event_id', 'sender.domain', "'group'", 'occurred_at']) }} as id,
    event_id,
    'domain' as identifier_type,
    sender.domain as identifier_value,
    'group' as entity_type,
    'gmail' as source,
    occurred_at
  FROM {{ ref('gmail_messages_base') }}
  WHERE sender.domain IS NOT NULL
  AND NOT sender.generic_domain
)
SELECT * FROM person_identifiers
UNION ALL
SELECT * FROM group_identifiers
```

Gmail relationship declarations (new):

```sql
-- gmail_relationship_declarations.sql
WITH email_memberships AS (
  SELECT
    {{ create_nexus_id('relationship_declaration', ['event_id', 'sender.email', 'sender.domain']) }} as id,
    event_id,
    sender.email as entity_a_identifier,
    'email' as entity_a_identifier_type,
    'person' as entity_a_type,
    sender.domain as entity_b_identifier,
    'domain' as entity_b_identifier_type,
    'group' as entity_b_type,
    'membership' as relationship_type,
    'a_to_b' as relationship_direction,
    'member' as entity_a_role,
    'organization' as entity_b_role,
    true as is_active,
    'gmail' as source,
    occurred_at
  FROM {{ ref('gmail_messages_base') }}
  WHERE sender.email IS NOT NULL
    AND sender.domain IS NOT NULL
    AND NOT sender.generic_domain
)
SELECT * FROM email_memberships
```

### Migration Steps

1. Source (L2): merge person/group → entity models; convert membership →
   relationship_declarations
2. Core (L3): unify to `entity_identifiers`, `entity_traits`,
   `relationship_declarations`
3. Resolution (L4): unify to resolved entity/relationship models with
   cardinality rules
4. Final (L5): create `entities`, `relationships`; add optional event‑based
   scoring
5. Update downstream queries/dashboards to new tables and field names

### Configuration

```yaml
vars:
  nexus_entity_types:
    [
      "person",
      "group",
      "contract",
      "product",
      "location",
      "task",
      "event_series",
    ]
  nexus_relationship_scoring_enabled: true
  nexus_relationship_recency_decay: 0.5
  nexus_entity_resolution_enabled: true
  sources:
    - name: salesforce
      events: true
      entities: true
      entity_types: ["person", "group", "contract"]
      relationships: true
      relationship_types: ["advisor_client", "customer_contract"]
    - name: workday
      events: false
      entities: true
      entity_types: ["person", "group"]
      relationships: true
      relationship_types: ["manager_employee"]
    - name: jira
      events: true
      entities: true
      entity_types: ["person", "task"]
      relationships: true
      relationship_types: ["assignee_task", "reporter_task"]
```

## Query Ergonomics (AWM example)

How many clients does this advisor have (regardless of client type):

```sql
SELECT
  COUNT(*) as total_clients,
  COUNT(CASE WHEN eb.entity_type = 'person' THEN 1 END) as individual_clients,
  COUNT(CASE WHEN eb.entity_type = 'group' THEN 1 END) as household_clients
FROM {{ ref('relationships') }} r
JOIN {{ ref('entities') }} ea ON r.entity_a_id = ea.entity_id
JOIN {{ ref('entities') }} eb ON r.entity_b_id = eb.entity_id
WHERE ea.entity_id = 'advisor_john'
  AND r.relationship_type = 'advisor_client'
  AND r.is_active = true
```

This rewrite makes relationships first‑class across all entity types, simplifies
model count, and keeps the deterministic, source‑declared nature of nexus
intact.
