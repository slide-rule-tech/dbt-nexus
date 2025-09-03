---
title: Package Overview
tags: [ai-context, overview, nexus, architecture]
summary: High-level overview of the dbt-nexus package for AI assistants.
---

# Package Overview

## Mission

The dbt-nexus package provides a standardized, source-agnostic dbt framework
that transforms scattered customer data into unified, operationally useful views
of people, companies, and events.

## Core Purpose

- **Unify customer data** from multiple sources (Gmail, Stripe, Shopify, etc.)
- **Resolve identities** across systems using recursive CTE-based deduplication
- **Track state changes** over time with timeline-based state management
- **Enable operational use** of data for sales, support, and AI tools

## Primary Entities

### Persons

Individual entities with:

- **Identifiers**: email, phone, user_id, etc.
- **Traits**: name, age, preferences, etc.
- **Timeline**: events and state changes over time

### Groups

Organizational entities (companies, accounts) with:

- **Identifiers**: domain, company_id, account_id, etc.
- **Traits**: company name, industry, size, etc.
- **Memberships**: relationships with persons

### Events

Timestamped actions/occurrences that:

- Generate identifiers and traits
- Trigger state changes
- Create relationship data

### States

Timeline-based tracking of entity conditions:

- **Base states**: Direct from source systems
- **Derived states**: Computed from multiple base states
- **Timeline**: state_entered_at, state_exited_at, is_current

## Architecture Layers

1. **Source Adapters**: Transform source data into standardized formats
2. **Event Log**: Core models for events, identifiers, traits
3. **Identity Resolution**: Deduplication logic producing resolved entities
4. **State Management**: Timeline tracking with derived states
5. **Final Tables**: Production-ready resolved entities

## Key Benefits

- **Operational Data**: Beyond dashboards - data that drives actions
- **Source Agnostic**: Works with any data source following naming conventions
- **Identity Resolution**: Automatic deduplication across systems
- **State Tracking**: Timeline-based state management
- **AI Ready**: Structured data perfect for AI/ML applications

## Database Support

- **Primary**: Snowflake, BigQuery (fully tested and optimized)
- **Secondary**: PostgreSQL, Redshift, Databricks
- **Recursive CTEs**: Optimized for each supported database

## Demo Data

Comprehensive demo data includes:

- **Gmail messages** with support tickets and billing
- **Google Calendar** events and meetings
- **Stripe** billing and payment records
- **Shopify** shop information and events

## Real-World Applications

- **Customer Support**: Complete context in one view
- **Sales Teams**: Full customer timeline for better conversion
- **AI Integration**: Structured data for AI tools
- **Marketing**: Up-to-date customer lists and segmentation
- **Operations**: Automated notifications and workflows
