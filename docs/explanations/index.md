---
title: Architecture & Concepts
tags: [explanations, concepts, architecture, design]
summary: Deep dives into how dbt-nexus works and why it's designed the way it is
---

# Architecture & Concepts

Understanding the "why" behind dbt-nexus design decisions and core concepts.

## Core Documentation

### 🏗️ **[Package Architecture](architecture.md)**

How dbt-nexus is structured, the layered approach, and why each layer exists.

### 🔍 **[Identity Resolution Logic](identity-resolution.md)**

Deep dive into how entities are matched, merged, and deduplicated across
sources.

### 🏷️ **[State Management Concepts](state-management.md)**

Timeline-based state tracking, derived states, and temporal data modeling.

### 🌊 **[Data Flow](data-flow.md)**

How data moves through the system from raw sources to final production tables.

### 🎯 **[Design Decisions](design-decisions.md)**

Architecture Decision Records (ADRs) documenting key design choices.

### ⚡ **[Performance Considerations](performance.md)**

How to optimize dbt-nexus for large datasets and complex identity graphs.

## When to Use This Section

Read these explanations when you want to:

- **Understand the reasoning** behind dbt-nexus design choices
- **Learn the theory** behind identity resolution algorithms
- **Grasp the concepts** before implementing complex features
- **Troubleshoot issues** by understanding root causes
- **Extend the package** with custom functionality

## Philosophy

dbt-nexus is built on several key principles:

### Source Agnostic

No vendor lock-in. Connect any data source through standardized adapters.

### Incremental by Design

Handle batch data processing with efficient incremental workflows.

### Identity-First

Everything revolves around resolving and tracking entity identities over time.

### Timeline Aware

Proper temporal modeling with state changes, effective dates, and audit trails.

### Composable

Modular design allows using individual components or the full system.

## Navigation Tips

- **Start with [Architecture](architecture.md)** for the big picture
- **Read [Identity Resolution](identity-resolution.md)** to understand the core
  algorithm
- **Check [Performance](performance.md)** when scaling to production
- **Reference [Design Decisions](design-decisions.md)** when extending the
  package
