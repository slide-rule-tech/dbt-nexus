---
title: dbt-nexus Documentation
summary:
  A comprehensive dbt package for customer identity resolution, event tracking,
  and entity management with advanced state management capabilities.
tags: [overview, nexus, identity-resolution, event-tracking]
---

# dbt-nexus Documentation

Welcome to the **dbt-nexus** package documentation! This package provides a
standardized, source-agnostic solution for building unified customer data
platforms with powerful identity resolution and state management capabilities.

## What is dbt-nexus?

dbt-nexus is a way of structuring all company data in your data warehouse so
it's **operationally** useful, not just good for dashboards. It's designed to
help you actually close sales, speed up customer support, and reduce churn.

Specifically, it's a dbt package that lets data engineers quickly merge and
organize **any** data source into a combined view of **people**, **companies**,
and **events** - creating a complete timeline of everything you know about your
customers.

dbt-nexus helps you:

- **🔗 Resolve identities** across multiple data sources and systems
- **📊 Track events** with standardized event logging that creates actionable
  timelines
- **👥 Manage entities** including persons, groups, and their relationships
- **🏷️ Handle states** with timeline-based state management
- **⚡ Scale efficiently** with incremental processing and optimized queries
- **🎯 Drive operations** - support teams, sales teams, and AI tools get
  complete customer context

## Quick Start

Get up and running with dbt-nexus in minutes:

```yaml
# packages.yml
packages:
  - local: path/to/dbt-nexus
```

```bash
dbt deps
```

[→ Follow the complete installation guide](getting-started/installation.md)

## Architecture Overview

### Image

![Database Schema Diagram](images/database-diagram.png)

### Mermaid

#### Final Tables

```mermaid
erDiagram
    events {
        string id PK
        timestamp occurred_at
        string type
        string name
        string source
    }

    persons {
        string id PK
        string email
        string name
        string phone
    }

    groups {
        string id PK
        string domain
        string name
        string shopify_id
    }

    memberships {
        string id PK
        string person_id FK
        string group_id FK
        string role
    }

    person_participants {
        string person_id FK
        string event_id FK
    }

    group_participants {
        string group_id FK
        string event_id FK
    }

    %% Relationships
    persons ||--o{ memberships : "has"
    groups ||--o{ memberships : "has"
    persons ||--o{ person_participants : "participates in"
    events ||--o{ person_participants : "has participants"
    groups ||--o{ group_participants : "participates in"
    events ||--o{ group_participants : "has participants"
```

#### Full

```mermaid
graph TD
    %% Raw Data Layer
    subgraph RawData["🔵 Raw Data"]
        RSD[raw_source_data<br/>• id: string PK<br/>• ...: string]
    end

    %% Source Event Log Layer
    subgraph SourceLog["🟠 Source Event Log"]
        SPT[source_person_traits<br/>• id: string PK<br/>• event_id: string FK<br/>• name: string]
        SPI[source_person_identifiers<br/>• id: string PK<br/>• event_id: string FK<br/>• email: string]
        SE[source_events<br/>• id: string PK<br/>• event_id: string FK<br/>• event_name: string<br/>• ...: string]
        SGI[source_group_identifiers<br/>• id: string PK<br/>• event_id: string FK<br/>• domain: string]
        SGT[source_group_traits<br/>• id: string PK<br/>• event_id: string FK<br/>• name: string]
        MI[membership_identifiers<br/>• event_id: string FK<br/>• occurred_at: timestamp<br/>• person_identifier: string<br/>• person_identifier_type: string<br/>• group_identifier: string<br/>• group_identifier_type: string<br/>• role: string]
    end

    %% Core Event Log Layer
    subgraph CoreLog["🔴 Core Event Log"]
        E[events<br/>• id: string PK<br/>• occurred_at: timestamp<br/>• type: string<br/>• name: string<br/>• source: string]
        PID[person_identifiers<br/>• id: string PK<br/>• event_id: string FK<br/>• email: string<br/>• user_id: string<br/>• phone: string]
        GID[group_identifiers<br/>• id: string PK<br/>• event_id: string FK<br/>• domain: string<br/>• myshopify_domain: string<br/>• shop_id: string]
        MID[membership_identifiers<br/>• id: string PK<br/>• event_id: string FK<br/>• person_identifier_id: string FK<br/>• group_identifier_id: string FK<br/>• role: string]
    end

    %% Identity Resolution Layer
    subgraph Identity["🟣 Identity Resolution"]
        RPI[resolved_person_identifiers<br/>• identifier_type: string<br/>• identifier_value: string<br/>• person_id: string]
        RGI[resolved_group_identifiers<br/>• identifier_type: string<br/>• identifier_value: string<br/>• group_id: string]
        RMI[resolved_membership_identifiers<br/>• id: string PK<br/>• membership_identifier_id: string FK<br/>• person_id: string FK<br/>• group_id: string FK<br/>• role: string]
        RPT[resolved_person_traits<br/>• trait_name: string<br/>• trait_value: string<br/>• person_id: string<br/>• occurred_at: timestamp]
        RGT[resolved_group_traits<br/>• trait_name: string<br/>• trait_value: string<br/>• group_id: string<br/>• occurred_at: timestamp]
    end

    %% Final Tables Layer
    subgraph Final["🟢 Final Tables"]
        P[persons<br/>• id: string PK<br/>• email: string<br/>• name: string<br/>• phone: string]
        G[groups<br/>• id: string PK<br/>• domain: string<br/>• name: string<br/>• shopify_id: string]
        M[memberships<br/>• id: string PK<br/>• person_id: string FK<br/>• group_id: string FK<br/>• role: string]
        PP[person_participants<br/>• group_id: string FK<br/>• event_id: string FK]
        GP[group_participants<br/>• group_id: string FK<br/>• event_id: string FK]
    end

    %% Data Flow Connections
    RSD -->|derives| SPT
    RSD -->|derives| SPI
    RSD -->|derives| SE
    RSD -->|derives| SGI
    RSD -->|derives| SGT
    RSD -->|derives| MI

    SPT -->|unions all sources to| RPT
    SPI -->|unions all sources to| PID
    SE -->|unions all sources to| E
    SGI -->|unions all sources to| GID
    SGT -->|unions all sources to| RGT
    MI -->|unions all sources to| MID

    E -->|has many| PID
    E -->|has many| GID
    E -->|has many| MID

    PID -->|resolves| RPI
    GID -->|resolves| RGI
    MID -->|resolves| RMI

    RPI -->|belongs to| P
    RGI -->|belongs to| G
    RMI -->|deduplicates to| M

    RPT -->|Most Recent| P
    RGT -->|Most Recent| G

    M -->|connects| P
    M -->|connects| G

    PP -->|references| P
    PP -->|references| E
    GP -->|references| G
    GP -->|references| E

    %% Styling
    classDef rawData fill:#dae8fc,stroke:#6c8ebf
    classDef sourceLog fill:#ffe6cc,stroke:#d79b00
    classDef coreLog fill:#f8cecc,stroke:#b85450
    classDef identity fill:#e1d5e7,stroke:#9673a6
    classDef finalTables fill:#d5e8d4,stroke:#82b366

    class RSD rawData
    class SPT,SPI,SE,SGI,SGT,MI sourceLog
    class E,PID,GID,MID coreLog
    class RPI,RGI,RMI,RPT,RGT identity
    class P,G,M,PP,GP finalTables
```

_Interactive database schema diagram showing the dbt-nexus data model structure
with the five-layer architecture: Raw Data, Source Event Log, Core Event Log,
Identity Resolution, and Final Tables._

> **Note**: To view the original diagram, open
> `docs/images/database-diagram.xml` in
> [diagrams.net](https://app.diagrams.net).
